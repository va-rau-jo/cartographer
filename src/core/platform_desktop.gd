extends RefCounted
## Desktop backend for Platform. Native FileDialog + direct FileAccess.

const IMAGE_FILTERS := ["*.jpg,*.jpeg,*.png,*.webp;Images"]
const ALBUM_FILTERS := ["*.ccalbum;Chrono Cartographer album"]

var _host: Node = null
var _dialog: FileDialog = null


func setup(host: Node) -> void:
	_host = host


func backend_name() -> String:
	return "desktop"


func supports_persistent_folder() -> bool:
	# We could remember the last path in profile.json; the editor treats this
	# as "no re-pick needed", which is true on desktop.
	return true


func pick_image_folder() -> void:
	_open_dialog(FileDialog.FILE_MODE_OPEN_DIR, [], _on_dir_selected)


func pick_album_file() -> void:
	_open_dialog(FileDialog.FILE_MODE_OPEN_FILE, ALBUM_FILTERS, _on_album_selected)


func read_file(file: Platform.PickedFile) -> PackedByteArray:
	var path := String(file.handle)
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		CCLog.error("platform", "cannot read %s (%d)" % [path, FileAccess.get_open_error()])
		return PackedByteArray()
	var bytes := f.get_buffer(f.get_length())
	f.close()
	return bytes


func deliver_file(bytes: PackedByteArray, filename: String, _mime: String) -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.current_file = filename
	dlg.use_native_dialog = true
	dlg.file_selected.connect(func(path: String) -> void:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			CCLog.error("platform", "cannot write %s" % path)
			return
		f.store_buffer(bytes)
		f.close()
		CCLog.info("platform", "wrote %s (%d bytes)" % [path, bytes.size()])
		dlg.queue_free()
	)
	_host.add_child(dlg)
	dlg.popup_centered_ratio(0.7)


func sync_user_fs() -> void:
	pass


# --- internals ---

func _open_dialog(mode: FileDialog.FileMode, filters: PackedStringArray, cb: Callable) -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = FileDialog.new()
	_dialog.file_mode = mode
	_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_dialog.filters = filters
	_dialog.use_native_dialog = true
	if mode == FileDialog.FILE_MODE_OPEN_DIR:
		_dialog.dir_selected.connect(cb)
	else:
		_dialog.file_selected.connect(cb)
	_dialog.canceled.connect(func() -> void: _host.pick_cancelled.emit())
	_host.add_child(_dialog)
	_dialog.popup_centered_ratio(0.7)


func _on_dir_selected(dir_path: String) -> void:
	var files: Array = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		CCLog.error("platform", "cannot open dir %s" % dir_path)
		_host.pick_cancelled.emit()
		return

	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not dir.current_is_dir():
			var pf := Platform.PickedFile.new()
			pf.name = name
			pf.relative_path = name
			pf.handle = dir_path.path_join(name)
			if pf.is_supported_image():
				pf.size = _file_size(pf.handle)
				pf.modified_unix = FileAccess.get_modified_time(pf.handle)
				files.append(pf)
		name = dir.get_next()
	dir.list_dir_end()

	CCLog.info("platform", "picked %d images from %s" % [files.size(), dir_path])
	if files.is_empty():
		_host.pick_cancelled.emit()
	else:
		_host.files_picked.emit(files)


func _on_album_selected(path: String) -> void:
	var pf := Platform.PickedFile.new()
	pf.name = path.get_file()
	pf.handle = path
	pf.size = _file_size(path)
	_host.files_picked.emit([pf])


func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return 0
	var n := f.get_length()
	f.close()
	return n
