extends Node
## Photographs the map widget, with whatever coastline data is available.
##
##   xvfb-run -a godot --path . --script tools/run_diag_map.gd
##
## With data/geo/coastlines.json present this is how you check that the bake
## looks like the world. Without it, it renders the synthetic fixture the tests
## use, so the widget itself — graticule, pin, readout, zoom — can still be
## looked at rather than only asserted about.

const OUT_DIR := "user://shots"
const SHOT_SIZE := Vector2i(900, 520)

## The same three rings tests/test_map.gd uses. Obviously not geography; it is
## here so the widget has something to draw when the real data is absent.
const FIXTURE := """
{"schema": 1, "source": "synthetic test fixture", "simplifiedDeg": 0.35,
 "lines": [[-80, -40, -40, -40, -40, 20, -80, 20, -80, -40],
           [-10, 35, 40, 35, 40, 60, -10, 60, -10, 35],
           [110, -40, 150, -40, 150, -10, 110, -10, 110, -40]]}
"""


func _ready() -> void:
	await get_tree().process_frame
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var window := get_window()
	window.size = SHOT_SIZE

	var real := CoastlineData.load_baked()
	var data := real
	var label := "data/geo/coastlines.json"
	if data.is_empty():
		data = CoastlineData.from_json(FIXTURE)
		label = "synthetic fixture (no baked data present)"

	var back := ColorRect.new()
	back.color = Color(0.07, 0.065, 0.06)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	window.add_child(back)

	var map := MapWidget.new()
	map.setup(data)
	map.position = Vector2(30, 30)
	map.size = Vector2(840, 420)
	window.add_child(map)

	var caption := Label.new()
	caption.text = "%s — %d lines, %d points" \
		% [label, data.polyline_count(), data.point_count()]
	caption.position = Vector2(30, 462)
	caption.add_theme_font_size_override("font_size", 15)
	caption.add_theme_color_override("font_color", Color(0.6, 0.62, 0.6))
	window.add_child(caption)

	# Two shots: the whole world, and zoomed in on a pin.
	map.set_pin_lat_lon(48.8566, 2.3522)
	for _i in 3:
		await get_tree().process_frame
	_save(window, "30_map_world")

	map._zoom_about(map.unit_to_pixel(Geo.to_unit(48.8566, 2.3522)), 4.0)
	for _i in 3:
		await get_tree().process_frame
	_save(window, "31_map_zoomed")

	print("")
	print("source         %s" % label)
	print("lines/points   %d / %d" % [data.polyline_count(), data.point_count()])
	print("pin            %s" % MapWidget.format_lat_lon(
		map.pin_lat_lon().x, map.pin_lat_lon().y))
	print("zoom           x%.1f" % map.zoom())
	get_tree().quit(0)


func _save(window: Window, name: String) -> void:
	var img := window.get_texture().get_image()
	var path := "%s/%s.png" % [OUT_DIR, name]
	print("  %-16s %s" % [name, "ok" if img.save_png(path) == OK else "FAILED"])
