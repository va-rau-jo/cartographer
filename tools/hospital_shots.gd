extends Node
## Photographs the opening scene at the moments that matter: the room as it
## fades up, the hold where she is standing at the bed, and the light rising as
## she goes in.
##
## The hospital room is the only scene nobody has looked at yet, and it is the
## first thing a player sees. It is also lit almost entirely by one grazing
## spotlight, which is exactly the setup that produced the gallery's shadow
## acne — so it needs eyes on it more than anything else here.

const OUT_DIR := "user://shots"
const SHOT_SIZE := Vector2i(960, 540)

const MOMENTS := [
	{"at": 1.2, "name": "20_hospital_dark",
	 "note": "Coming up out of black: what the player sees first."},
	{"at": 4.0, "name": "21_hospital_room",
	 "note": "THE ROOM: bed, window, her at his side, camera still pushing."},
	{"at": 8.5, "name": "22_hospital_hold",
	 "note": "The hold, with the prompt up and the camera at its closest."},
	{"at": 11.5, "name": "23_hospital_rise",
	 "note": "She has taken his hand and the light is rising."},
]


func _ready() -> void:
	await get_tree().process_frame
	_run()


## Close on the pillow, from above and to the side.
func _head_close_up(scene: Node3D, window: Window) -> void:
	var head: Node3D = scene.get_node_or_null("RestingHead")
	if head == null:
		return
	var cam := Camera3D.new()
	cam.name = "HeadCamera"
	window.add_child(cam)
	cam.fov = 38.0
	var at := head.global_position
	cam.position = at + Vector3(0.62, 0.52, 0.72)
	cam.look_at(at, Vector3.UP)
	cam.make_current()
	for _i in 4:
		await get_tree().process_frame
	var img := window.get_texture().get_image()
	if img.save_png("%s/24_hospital_head.png" % OUT_DIR) == OK:
		print("  %-20s  %s" % ["24_hospital_head",
			"Close on the pillow: does he read as a man asleep?"])


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var window := get_window()
	window.size = SHOT_SIZE

	var script := load("res://src/hospital/hospital_scene.gd") as GDScript
	if script == null or not script.can_instantiate():
		# Almost always a parse error in the scene script. Say so and exit
		# rather than dying mid-run and hanging until something kills us.
		print("hospital_scene.gd did not compile")
		get_tree().quit(3)
		return
	var scene: Node3D = script.new()
	scene.name = "Hospital"
	window.add_child(scene)

	for _i in 8:
		await get_tree().process_frame

	var written := 0
	var elapsed := 0.0
	var moment := 0

	while moment < MOMENTS.size() and elapsed < 40.0:
		await get_tree().process_frame
		elapsed += get_process_delta_time()

		# Take his hand for her, so the rise is photographed rather than
		# waiting on a keypress nobody is here to make.
		if elapsed > 9.5 and scene.has_method("_begin_rise"):
			scene._begin_rise()

		if elapsed < float(MOMENTS[moment]["at"]):
			continue

		var img := window.get_texture().get_image()
		var path := "%s/%s.png" % [OUT_DIR, MOMENTS[moment]["name"]]
		if img.save_png(path) == OK:
			written += 1
			print("  %-20s  t=%5.1fs  %s"
				% [MOMENTS[moment]["name"], elapsed, MOMENTS[moment]["note"]])
		moment += 1

	# A close look at the pillow. The head is the one thing in this scene that
	# has to read, and at the staged distance it is ten pixels tall.
	await _head_close_up(scene, window)

	print("")
	print("room           %.1f x %.1f x %.1f m"
		% [scene.ROOM_WIDTH, scene.ROOM_DEPTH, scene.ROOM_HEIGHT])
	var meshes := scene.find_children("*", "MeshInstance3D", true, false)
	print("meshes         %d" % meshes.size())
	print("lights         %d" % scene.find_children("*", "Light3D", true, false).size())
	var head: RestingHead = scene.get_node_or_null("RestingHead")
	if head == null:
		print("resting head   MISSING — the bed is empty")
	else:
		print("resting head   %d tris, %d drawn pixels, %.2f x %.2f m at y=%.2f"
			% [head.total_triangles(), head.filled_pixels(),
			   head.size_metres().x, head.size_metres().y,
			   head.global_position.y])
	print("wrote %d shots to %s"
		% [written, ProjectSettings.globalize_path(OUT_DIR)])

	get_tree().quit(0 if written == MOMENTS.size() else 1)
