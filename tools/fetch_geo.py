#!/usr/bin/env python3
"""Bake the world's coastline into data/geo/coastlines.json.

The map needs an outline to draw. The source is Natural Earth's 110m physical
coastline — public domain, about 200 KB of GeoJSON — and this turns it into the
flat, simplified form CoastlineData reads.

    python tools/fetch_geo.py                     # download, simplify, write
    python tools/fetch_geo.py --from ne.geojson   # use a file you already have
    python tools/fetch_geo.py --tolerance 0.25    # keep more detail
    python tools/fetch_geo.py --check             # just report what is there

Why this is a script you have to run, rather than a file in the repository:
every host that serves Natural Earth is blocked from the environment the rest
of this project was written in (403 at the proxy, from both the build container
and the desktop). Inventing a coastline instead would have produced something
that looked plausible and was wrong, so the map ships as a graticule and the
guess panel falls back to its place list until this has been run once.

Standard library only, on purpose: no pip install before you can see a map.

Licensing: Natural Earth is public domain, no attribution required. The
`source` field is recorded in the output anyway, because a dataset with no
provenance is a dataset nobody can check.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import sys
import urllib.error
import urllib.request
import zipfile

# Tried in order. The first two are GeoJSON; the third is the shapefile zip,
# which needs no parsing here because we only reach it if the others fail and
# we then tell you to extract it yourself.
SOURCES = [
    "https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/"
    "geojson/ne_110m_coastline.geojson",
    "https://cdn.jsdelivr.net/gh/nvkelso/natural-earth-vector@master/"
    "geojson/ne_110m_coastline.geojson",
    "https://naciscdn.org/naturalearth/110m/physical/ne_110m_coastline.zip",
]

SOURCE_LABEL = "Natural Earth 110m physical coastline (public domain)"
OUT_PATH = os.path.join("data", "geo", "coastlines.json")
SCHEMA = 1

# Degrees. 0.35 keeps every recognisable bay and headland at the zoom levels
# the map allows, and drops roughly two thirds of the points.
DEFAULT_TOLERANCE = 0.35

# Rings whose whole extent is under this many degrees are islands too small to
# read on screen at any zoom the map offers, and there are hundreds of them.
# Judged by extent, not by point count: a four-point speck is still a speck.
MIN_SPAN_DEG = 0.6

TIMEOUT = 30


def fetch(url: str) -> bytes:
    request = urllib.request.Request(
        url, headers={"User-Agent": "chrono-cartographer/1.0"}
    )
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read()


def load_remote() -> dict:
    errors = []
    for url in SOURCES:
        sys.stderr.write("trying %s\n" % url)
        try:
            raw = fetch(url)
        except (urllib.error.URLError, urllib.error.HTTPError, OSError) as exc:
            errors.append("%s -> %s" % (url, exc))
            continue

        if url.endswith(".zip"):
            # The shapefile bundle. Converting a .shp without pyshp is more
            # code than this tool deserves, so say what to do instead.
            with zipfile.ZipFile(io.BytesIO(raw)) as archive:
                names = ", ".join(archive.namelist())
            raise SystemExit(
                "Only the shapefile mirror is reachable (%s).\n"
                "Download the GeoJSON by hand from\n"
                "  %s\n"
                "and re-run with --from <that file>." % (names, SOURCES[0])
            )

        return json.loads(raw.decode("utf-8"))

    raise SystemExit(
        "Could not reach any Natural Earth mirror:\n  "
        + "\n  ".join(errors)
        + "\n\nDownload ne_110m_coastline.geojson yourself and re-run with\n"
        "  python tools/fetch_geo.py --from <path to that file>"
    )


def load_local(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def rings(geojson: dict) -> list[list[tuple[float, float]]]:
    """Every LineString in the file, as lists of (lon, lat)."""
    out: list[list[tuple[float, float]]] = []

    def take(coords, depth: int) -> None:
        # A coastline file is LineString / MultiLineString, but being tolerant
        # here costs four lines and accepts polygons too.
        if not coords:
            return
        first = coords[0]
        if isinstance(first, (int, float)):
            return
        if isinstance(first[0], (int, float)):
            out.append([(float(x), float(y)) for x, y in coords])
            return
        for child in coords:
            take(child, depth + 1)

    for feature in geojson.get("features", []):
        geometry = feature.get("geometry") or {}
        take(geometry.get("coordinates"), 0)

    if not out and "coordinates" in geojson:
        take(geojson["coordinates"], 0)
    return out


def point_line_distance(p, a, b) -> float:
    ax, ay = a
    bx, by = b
    px, py = p
    dx, dy = bx - ax, by - ay
    length_sq = dx * dx + dy * dy
    if length_sq < 1e-12:
        return ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
    t = ((px - ax) * dx + (py - ay) * dy) / length_sq
    t = max(0.0, min(1.0, t))
    nx, ny = ax + dx * t, ay + dy * t
    return ((px - nx) ** 2 + (py - ny) ** 2) ** 0.5


def simplify(line, tolerance: float):
    """Douglas-Peucker, iterative — some rings have thousands of points."""
    if len(line) <= 2 or tolerance <= 0.0:
        return line

    keep = [False] * len(line)
    keep[0] = keep[-1] = True
    stack = [(0, len(line) - 1)]

    while stack:
        start, end = stack.pop()
        worst, worst_at = -1.0, -1
        for i in range(start + 1, end):
            d = point_line_distance(line[i], line[start], line[end])
            if d > worst:
                worst, worst_at = d, i
        if worst > tolerance and worst_at > 0:
            keep[worst_at] = True
            stack.append((start, worst_at))
            stack.append((worst_at, end))

    return [p for p, k in zip(line, keep) if k]


def span(line) -> float:
    xs = [p[0] for p in line]
    ys = [p[1] for p in line]
    return max(max(xs) - min(xs), max(ys) - min(ys))


def bake(geojson: dict, tolerance: float, source_label: str) -> dict:
    lines_in = rings(geojson)
    if not lines_in:
        raise SystemExit("that file has no line geometry in it")

    points_in = sum(len(line) for line in lines_in)
    out_lines = []
    dropped = 0

    for line in lines_in:
        if len(line) < 2:
            continue
        if span(line) < MIN_SPAN_DEG:
            dropped += 1
            continue
        reduced = simplify(line, tolerance)
        if len(reduced) < 2:
            dropped += 1
            continue
        flat = []
        for lon, lat in reduced:
            flat.append(round(lon, 4))
            flat.append(round(lat, 4))
        out_lines.append(flat)

    points_out = sum(len(line) // 2 for line in out_lines)
    sys.stderr.write(
        "%d lines / %d points  ->  %d lines / %d points "
        "(%.0f%% kept, %d tiny islands dropped)\n"
        % (
            len(lines_in),
            points_in,
            len(out_lines),
            points_out,
            100.0 * points_out / max(points_in, 1),
            dropped,
        )
    )

    return {
        "schema": SCHEMA,
        "source": source_label,
        "simplifiedDeg": tolerance,
        "lines": out_lines,
    }


def check(path: str) -> int:
    if not os.path.exists(path):
        print("no coastline data at %s" % path)
        print("the map will draw a graticule only, and the guess panel will")
        print("fall back to its place list. Run this tool without --check.")
        return 1

    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    lines = data.get("lines", [])
    points = sum(len(line) // 2 for line in lines)
    print("%s" % path)
    print("  schema     %s" % data.get("schema"))
    print("  source     %s" % data.get("source", "(unrecorded)"))
    print("  simplified %s deg" % data.get("simplifiedDeg"))
    print("  lines      %d" % len(lines))
    print("  points     %d" % points)
    print("  size       %.0f KB" % (os.path.getsize(path) / 1024.0))
    return 0 if data.get("schema") == SCHEMA and points > 0 else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--from", dest="source", help="a local GeoJSON file")
    parser.add_argument("--out", default=OUT_PATH, help="output path")
    parser.add_argument(
        "--tolerance",
        type=float,
        default=DEFAULT_TOLERANCE,
        help="simplification tolerance in degrees (default %.2f)"
        % DEFAULT_TOLERANCE,
    )
    parser.add_argument(
        "--check", action="store_true", help="report on the existing file"
    )
    args = parser.parse_args()

    if args.check:
        return check(args.out)

    if args.source:
        geojson = load_local(args.source)
        # Record what it actually came from. A file labelled Natural Earth that
        # is not Natural Earth is worse than one labelled honestly.
        label = "local file: %s" % os.path.basename(args.source)
    else:
        geojson = load_remote()
        label = SOURCE_LABEL
    baked = bake(geojson, args.tolerance, label)

    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as handle:
        json.dump(baked, handle, separators=(",", ":"))

    size_kb = os.path.getsize(args.out) / 1024.0
    print("wrote %s (%.0f KB)" % (args.out, size_kb))
    print("the map will pick it up the next time the game starts.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
