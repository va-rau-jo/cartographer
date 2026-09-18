extends SceneTree
## Saves the three drawn views of both figures as flat PNGs, one pixel per
## canvas pixel scaled up, so a drawing can be judged without a 3D render
## in the way.
##
##   godot --headless --path . --script tools/draw_canvases.gd

const SCALE := 8


func _initialize() -> void:
	var dir := "user://canvases"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	for spec in [["her", 0], ["him", 1]]:
		var figure: PixelFigure = PixelFigure.new()
		figure.form = spec[1]
		figure.palette = PixelFigure.Palette.new() if spec[1] == 0 \
			else PixelFigure.Palette.husband()
		var colours: Array = figure.palette.to_array()

		var views := {
			"front": figure._front_canvas(),
			"side": figure._side_canvas(),
			"back": figure._back_canvas(),
		}
		for key in views.keys():
			var img := _render(views[key], colours)
			var path := "%s/%s_%s.png" % [dir, spec[0], key]
			print("%-12s %s" % ["%s %s" % [spec[0], key],
				"ok" if img.save_png(path) == OK else "FAILED"])
		figure.free()
	quit(0)


func _render(canvas: PackedByteArray, colours: Array) -> Image:
	var w := PixelFigure.SPRITE_WIDTH
	var h := PixelFigure.SPRITE_HEIGHT
	var img := Image.create_empty(w * SCALE, h * SCALE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.09, 0.09))
	for y in h:
		for x in w:
			var v: int = canvas[x + w * y]
			if v == PixelFigure.EMPTY:
				continue
			var colour: Color = colours[v]
			# Canvas y counts up from the feet; images count down from the top.
			img.fill_rect(Rect2i(x * SCALE, (h - 1 - y) * SCALE, SCALE, SCALE),
				colour)
	return img
