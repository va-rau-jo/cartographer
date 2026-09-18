extends RefCounted
## Web backend for Platform.
##
## Two things matter here and both are easy to get wrong:
##
## 1. Callbacks created with JavaScriptBridge.create_callback() must be held in
##    a member variable. If they are garbage-collected before JS invokes them,
##    the call silently does nothing. Hence _cb_picked / _cb_read below.
##
## 2. Files must be read as ArrayBuffer and converted with
##    js_buffer_to_packed_byte_array(). Reading as text (the approach in most
##    tutorials) corrupts image bytes.
##
## The File objects from <input> are lazy handles, so listing a 1000-image
## folder is instant and we only pay for the ten we actually use.

const _BOOTSTRAP := """
window.__cc = window.__cc || { files: [], readBuf: null, readErr: null, pick: 0 };

// One picker for every kind of pick, and one place that decides a pick is
// over. A cancelled <input type=file> fires no change event at all, and the
// `cancel` event only exists in newer browsers, so there are three ways out:
// change, cancel, and — for everything older — the window regaining focus
// with no file chosen. Without that last one the UI waits forever.
window.__ccPick = function(opts) {
  const token = ++window.__cc.pick;
  const i = document.createElement('input');
  i.type = 'file';
  if (opts.directory) { i.webkitdirectory = true; i.multiple = true; }
  if (opts.accept) { i.accept = opts.accept; }
  i.style.display = 'none';
  document.body.appendChild(i);

  let settled = false;
  const cleanup = function() { if (i.parentNode) { i.parentNode.removeChild(i); } };

  const finish = function(files) {
	if (settled || token !== window.__cc.pick) { return; }
	settled = true;
	cleanup();
	window.__cc.files = files || [];
	const meta = window.__cc.files.map(function(f, idx) {
	  return { idx: idx, name: f.name, rel: f.webkitRelativePath || f.name,
			   size: f.size, mtime: Math.floor((f.lastModified || 0) / 1000) };
	});
	window.__ccOnPicked(JSON.stringify(meta));
  };

  i.onchange = function() { finish(Array.from(i.files)); };
  i.oncancel = function() { finish([]); };

  // The fallback: a focus event that arrives with nothing selected means the
  // dialog was dismissed. Delayed, because on some browsers focus comes back
  // a moment before the change event does.
  const onFocus = function() {
	window.removeEventListener('focus', onFocus);
	setTimeout(function() {
	  if (!settled && (!i.files || i.files.length === 0)) { finish([]); }
	}, 1200);
  };
  window.addEventListener('focus', onFocus);

  i.click();
};
window.__ccPickImages = function() {
  window.__ccPick({ directory: true,
					accept: 'image/jpeg,image/png,image/webp' });
};
window.__ccPickAlbum = function() {
  window.__ccPick({ accept: '.ccalbum,application/zip' });
};
window.__ccPickArchive = function() {
  window.__ccPick({ accept: '.zip,.ccalbum,application/zip' });
};
window.__ccReadFile = function(idx, token) {
  const f = window.__cc.files[idx];
  window.__cc.readBuf = null;
  window.__cc.readErr = null;
  if (!f) { window.__cc.readErr = 'no file at index ' + idx; window.__ccOnRead(token); return; }
  f.arrayBuffer().then(function(ab) {
	window.__cc.readBuf = new Uint8Array(ab);
	window.__ccOnRead(token);
  }).catch(function(e) {
	window.__cc.readErr = String(e);
	window.__ccOnRead(token);
  });
};
"""

var _host: Node = null
var _cc: JavaScriptObject = null
var _cb_picked: JavaScriptObject = null
var _cb_read: JavaScriptObject = null

var _read_token := 0
signal _read_done(token: int)


func setup(host: Node) -> void:
	_host = host
	JavaScriptBridge.eval(_BOOTSTRAP, true)

	_cb_picked = JavaScriptBridge.create_callback(_on_js_picked)
	_cb_read = JavaScriptBridge.create_callback(_on_js_read)

	var window := JavaScriptBridge.get_interface("window")
	window.__ccOnPicked = _cb_picked
	window.__ccOnRead = _cb_read

	_cc = JavaScriptBridge.get_interface("__cc")


func backend_name() -> String:
	return "web"


func supports_persistent_folder() -> bool:
	# The File System Access API would give us re-grantable handles, but it is
	# Chrome/Edge only. Treat "pick again" as the baseline; see plan §5.2.
	return false


func pick_image_folder() -> void:
	JavaScriptBridge.eval("window.__ccPickImages();", true)


func pick_album_file() -> void:
	JavaScriptBridge.eval("window.__ccPickAlbum();", true)


func pick_photo_archive() -> void:
	JavaScriptBridge.eval("window.__ccPickArchive();", true)


func read_file(file: Platform.PickedFile) -> PackedByteArray:
	var idx := int(file.handle)
	_read_token += 1
	var token := _read_token

	JavaScriptBridge.eval("window.__ccReadFile(%d, %d);" % [idx, token], true)

	# Wait for this specific read. Concurrent reads are possible, so loop until
	# our own token comes back.
	while true:
		var done_token: int = await _read_done
		if done_token == token:
			break

	var err = _cc.readErr
	if err != null:
		CCLog.error("platform", "read failed for %s: %s" % [file.name, str(err)])
		return PackedByteArray()

	var buf: JavaScriptObject = _cc.readBuf
	if buf == null:
		CCLog.error("platform", "read returned no buffer for %s" % file.name)
		return PackedByteArray()

	return JavaScriptBridge.js_buffer_to_packed_byte_array(buf)


## The browser owns the download from here: it goes to wherever the user's
## browser puts downloads, and there is no callback to say it landed. So the
## report names the file and says nothing about a path.
func deliver_file(bytes: PackedByteArray, filename: String, mime: String) -> void:
	JavaScriptBridge.download_buffer(bytes, filename, mime)
	CCLog.info("platform", "offered download %s (%d bytes)" % [filename, bytes.size()])
	_host.report_delivered(true, filename)


func sync_user_fs() -> void:
	JavaScriptBridge.force_fs_sync()


# --- JS callbacks. Each receives a single Array of the JS arguments. ---

func _on_js_picked(args: Array) -> void:
	var raw: String = str(args[0]) if args.size() > 0 else "[]"
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_ARRAY:
		CCLog.error("platform", "bad pick payload")
		_host.report_cancelled()
		return

	var files: Array = []
	for entry in parsed:
		var pf := Platform.PickedFile.new()
		pf.name = entry.get("name", "")
		pf.relative_path = entry.get("rel", pf.name)
		pf.size = int(entry.get("size", 0))
		pf.modified_unix = int(entry.get("mtime", 0))
		pf.handle = int(entry.get("idx", -1))
		files.append(pf)

	CCLog.info("platform", "picked %d files" % files.size())
	_host.report_picked(files)


func _on_js_read(args: Array) -> void:
	var token := int(args[0]) if args.size() > 0 else -1
	_read_done.emit(token)
