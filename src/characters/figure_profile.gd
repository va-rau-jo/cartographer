class_name FigureProfile
extends RefCounted
## How she looks, and where that is remembered.
##
## The brief asked for a customizable player model, and for a drawn figure that
## means one thing: the palette. Five colours — skin, hair, dress, cardigan,
## shoes — and PixelFigure derives every shade from them, so a single swatch
## moves the base tone and the form shading follows it (see Palette._shade).
##
## Saved to `user://profile.json`, which on the web is IndexedDB behind
## Platform.sync_user_fs(). Deliberately not part of the album: the album is
## the gift's *content* and travels between people, while this is the player's
## own preference and stays on the machine she plays on.

const PATH := "user://profile.json"
const SCHEMA := 1

## Presets, per slot. Swatches rather than a colour wheel: five wheels is a
## paint program, and the point is to look like her in under a minute.
## Deliberately narrow ranges — these are an old woman's colours, not a
## character creator's.
const SKINS := [
	Color(0.96, 0.85, 0.78), Color(0.91, 0.76, 0.66),
	Color(0.83, 0.65, 0.52), Color(0.70, 0.52, 0.40),
	Color(0.52, 0.37, 0.28), Color(0.36, 0.25, 0.19),
]
const HAIRS := [
	Color(0.92, 0.91, 0.89), Color(0.80, 0.78, 0.75),
	Color(0.66, 0.63, 0.60), Color(0.74, 0.62, 0.42),
	Color(0.52, 0.36, 0.24), Color(0.28, 0.22, 0.19),
]
const DRESSES := [
	Color(0.62, 0.42, 0.46), Color(0.44, 0.48, 0.60),
	Color(0.40, 0.52, 0.44), Color(0.68, 0.58, 0.40),
	Color(0.52, 0.40, 0.56), Color(0.34, 0.34, 0.38),
]
const WRAPS := [
	Color(0.33, 0.38, 0.48), Color(0.58, 0.50, 0.38),
	Color(0.46, 0.52, 0.46), Color(0.64, 0.56, 0.56),
	Color(0.38, 0.34, 0.40), Color(0.74, 0.70, 0.62),
]
const SHOES := [
	Color(0.22, 0.18, 0.17), Color(0.34, 0.26, 0.20),
	Color(0.44, 0.40, 0.38), Color(0.28, 0.24, 0.30),
]

var skin: Color = SKINS[1]
var hair: Color = HAIRS[1]
var dress: Color = DRESSES[0]
var wrap: Color = WRAPS[0]
var shoe: Color = SHOES[0]


## The palette PixelFigure builds from. Everything else — the shades, the
## contact edge — is derived from these five.
func to_palette() -> PixelFigure.Palette:
	var palette := PixelFigure.Palette.new()
	palette.skin = skin
	palette.hair = hair
	palette.dress = dress
	palette.wrap = wrap
	palette.shoe = shoe
	return palette


func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA,
		"figure": {
			"skin": skin.to_html(false),
			"hair": hair.to_html(false),
			"dress": dress.to_html(false),
			"wrap": wrap.to_html(false),
			"shoe": shoe.to_html(false),
		},
	}


static func from_dict(data: Dictionary) -> FigureProfile:
	var profile := FigureProfile.new()
	if int(data.get("schema", 0)) != SCHEMA:
		# Same rule as the album manifest: refuse rather than guess. A default
		# figure is a fine outcome; a figure built from misread fields is not.
		return profile

	var figure: Dictionary = data.get("figure", {})
	profile.skin = _colour(figure, "skin", profile.skin)
	profile.hair = _colour(figure, "hair", profile.hair)
	profile.dress = _colour(figure, "dress", profile.dress)
	profile.wrap = _colour(figure, "wrap", profile.wrap)
	profile.shoe = _colour(figure, "shoe", profile.shoe)
	return profile


static func _colour(data: Dictionary, key: String, fallback: Color) -> Color:
	var raw := str(data.get(key, "")).strip_edges()
	if raw.is_empty() or not Color.html_is_valid(raw):
		return fallback
	return Color.html(raw)


# ------------------------------------------------------------------- disk

## Load the saved figure, or the default one. Never fails: a missing or
## unreadable profile is simply the default, because the alternative is a
## player who cannot get into the game.
static func load_saved(path: String = PATH) -> FigureProfile:
	if not FileAccess.file_exists(path):
		return FigureProfile.new()

	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return FigureProfile.new()

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		CCLog.warn("profile", "%s is not valid JSON; using the default" % path)
		return FigureProfile.new()

	return from_dict(parsed)


## Returns true when it actually wrote. Callers on web should follow with
## Platform.sync_user_fs(), which is why this does not call it itself — the
## data layer stays free of the autoloads (see the README's first rule).
func save(path: String = PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		CCLog.error("profile", "cannot write %s (error %d)"
			% [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	CCLog.info("profile", "saved the figure to %s" % path)
	return true


## Equal to eight bits per channel.
##
## Colours are stored in the profile as hex and end up in the mesh as 8-bit
## vertex colours, so a swatch that went to disk and came back is no longer
## exactly the constant it started as. Color.is_equal_approx is far tighter
## than that, which meant a saved figure opened the customization screen with
## none of its own swatches ringed.
const CHANNEL_EPSILON := 0.005


static func same_colour(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= CHANNEL_EPSILON \
		and absf(a.g - b.g) <= CHANNEL_EPSILON \
		and absf(a.b - b.b) <= CHANNEL_EPSILON


## Index of `colour` among `options`, or -1. Used by the customization screen
## to show which swatch is the current one.
static func index_of(options: Array, colour: Color) -> int:
	for i in options.size():
		if same_colour(options[i] as Color, colour):
			return i
	return -1
