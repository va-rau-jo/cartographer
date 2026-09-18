extends Node
## Autoload: Platform
##
## The single place where web and desktop differ. Everything else in the
## codebase calls these methods and never checks OS.has_feature("web").
##
## Both backends are async-by-signal rather than async-by-await, because the
## web file picker is driven by a JS callback that can fire at any time (or
## never, if the user cancels the dialog).

## Emitted once per successful pick. `files` is Array[PickedFile].
signal files_picked(files: Array)
## Emitted when a pick yields nothing — user cancelled, or every file was
## filtered out.
signal pick_cancelled()

## What kind of pick is in flight, so a screen can say so and can refuse to
## start a second one. NONE between picks.
enum Picking { NONE, IMAGE_FOLDER, ALBUM_FILE, PHOTO_ARCHIVE }

## A file the user chose. `bytes` is null until read() resolves, because the
## whole point on web is that a 1000-file folder stays lazy.
class PickedFile extends RefCounted:
	var name: String = ""          ## basename, e.g. "IMG_0421.JPG"
	var relative_path: String = "" ## path within the picked folder, if any
	var size: int = 0
	var modified_unix: int = 0
	var handle: Variant = null     ## backend-specific: JS File, or absolute path

	func extension() -> String:
		return name.get_extension().to_lower()

	func is_supported_image() -> bool:
		return extension() in ["jpg", "jpeg", "png", "webp"]


var _backend: RefCounted = null
var _picking: Picking = Picking.NONE


func _ready() -> void:
	_ensure_backend()


## Backends are created lazily rather than only in _ready(), because autoload
## ordering is not guaranteed and the headless test runner never calls _ready()
## at all. Every public method goes through here.
func _ensure_backend() -> void:
	if _backend != null:
		return
	if OS.has_feature("web"):
		_backend = load("res://src/web/platform_web.gd").new()
	else:
		_backend = load("res://src/core/platform_desktop.gd").new()
	_backend.setup(self)
	CCLog.info("platform", "backend: %s" % _backend.backend_name())


func backend_name() -> String:
	_ensure_backend()
	return _backend.backend_name()


## Ask the user for a folder of images. Resolves via files_picked/pick_cancelled.
func pick_image_folder() -> void:
	_ensure_backend()
	_picking = Picking.IMAGE_FOLDER
	_backend.pick_image_folder()


## Ask the user for a single .ccalbum file.
func pick_album_file() -> void:
	_ensure_backend()
	_picking = Picking.ALBUM_FILE
	_backend.pick_album_file()


## Ask the user for a .zip of photographs — a Google Photos download, or a
## Takeout export. Same resolution as the others.
func pick_photo_archive() -> void:
	_ensure_backend()
	_picking = Picking.PHOTO_ARCHIVE
	_backend.pick_photo_archive()


## What is in flight, if anything.
func picking() -> Picking:
	return _picking


func is_picking() -> bool:
	return _picking != Picking.NONE


## Backends call these instead of emitting the signals themselves, so that
## every pick resolves exactly once.
##
## This exists because of a real bug: a cancelled dialog left the UI's button
## disabled forever. The desktop FileDialog's `canceled` signal does not
## always arrive when the OS draws the dialog natively, and a cancelled
## <input type=file> fires no event at all in older browsers. Rather than
## trusting either, the backends report through here, a pick that is already
## resolved is ignored, and the screens do not disable anything they would
## then have to re-enable.
func report_picked(files: Array) -> void:
	if _picking == Picking.NONE:
		return
	_picking = Picking.NONE
	if files.is_empty():
		pick_cancelled.emit()
	else:
		files_picked.emit(files)


func report_cancelled() -> void:
	if _picking == Picking.NONE:
		return
	_picking = Picking.NONE
	pick_cancelled.emit()


## Read one picked file's bytes. This is the expensive call on web, so only
## ever do it for files you are actually going to use.
func read_file(file: PickedFile) -> PackedByteArray:
	_ensure_backend()
	return await _backend.read_file(file)


## Hand the user a finished file. On web this is a browser download; on
## desktop it writes to a chosen path.
func deliver_file(bytes: PackedByteArray, filename: String, mime: String = "application/octet-stream") -> void:
	_ensure_backend()
	_backend.deliver_file(bytes, filename, mime)


## Flush user:// so it survives a page refresh. No-op on desktop.
func sync_user_fs() -> void:
	_ensure_backend()
	_backend.sync_user_fs()


## True when this backend can keep a folder handle across sessions, so the
## editor can offer "resume where you left off" rather than "pick again".
func supports_persistent_folder() -> bool:
	_ensure_backend()
	return _backend.supports_persistent_folder()
