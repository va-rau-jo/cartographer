extends SceneTree
## Renders the drawn embrace flat, one pixel per canvas pixel, so the pose can
## be judged without the hall's lighting and the camera in the way.
##
##   godot --headless --path . --script tools/draw_embrace.gd

const SCALE := 10


func _initialize() -> void:
	var dir := "user://canvases"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))

	var e: EmbraceFigure = EmbraceFigure.new()
	e.build(PixelFigure.Palette.new(), PixelFigure.Palette.for_trousers())
	var canvas: PackedByteArray = e._draw()

	# The same table build() makes: her eleven tones, then his, then the edge.
	var colours: Array = [Color.TRANSPARENT]
	var her_tones: Array = PixelFigure.Palette.new().to_array()
	var his_tones: Array = PixelFigure.Palette.for_trousers().to_array()
	for i in range(1, her_tones.size()):
		colours.append(her_tones[i])
	for i in range(1, his_tones.size()):
		colours.append(his_tones[i])
	colours.append(Color(0.10, 0.085, 0.08))

	var w := EmbraceFigure.CANVAS_WIDTH
	var h := EmbraceFigure.CANVAS_HEIGHT
	var img := Image.create_empty(w * SCALE, h * SCALE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.10, 0.09, 0.09))
	for y in h:
		for x in w:
			var v: int = canvas[x + w * y]
			if v == 0:
				continue
			img.fill_rect(Rect2i(x * SCALE, (h - 1 - y) * SCALE, SCALE, SCALE),
				colours[v] as Color)
	print("embrace: %s" % ("ok" if img.save_png("%s/embrace.png" % dir) == OK
		else "FAILED"))
	e.free()
	quit(0)
