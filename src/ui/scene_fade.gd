class_name SceneFade
extends CanvasLayer
## A full-screen fade, in or out, in any colour.
##
## Every scene in the game arrives and leaves through one of these, so it lives
## in one place: the hospital fades up from black and out to white, the gallery
## fades in from that same white, and the ending has its own (it needs to
## interleave a fade with camera work, so it keeps its own rectangle).
##
## Usage:
##   var fade := SceneFade.new()
##   add_child(fade)
##   fade.fade_in(Color.WHITE, 2.5)          # from white to clear
##   await fade.fade_out(Color.WHITE, 3.0)   # to white, awaitable

signal finished()

const DEFAULT_TIME := 1.5

var _rect: ColorRect = null
var _from := 0.0
var _to := 0.0
var _time := DEFAULT_TIME
var _clock := 0.0
var _running := false


func _init() -> void:
	layer = 40


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.color = Color(0, 0, 0, 0)
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	# Whatever was requested before the node entered the tree.
	_rect.color.a = _from


## Start opaque in `colour` and clear to nothing.
func fade_in(colour: Color = Color.BLACK, seconds: float = DEFAULT_TIME) -> Signal:
	return _run(colour, 1.0, 0.0, seconds)


## Cover the screen in `colour`.
func fade_out(colour: Color = Color.BLACK, seconds: float = DEFAULT_TIME) -> Signal:
	return _run(colour, 0.0, 1.0, seconds)


## Sit at a fixed opacity without animating — for a scene that wants to open
## already covered and decide later.
func hold(colour: Color, alpha: float) -> void:
	_running = false
	_from = alpha
	_to = alpha
	if _rect != null:
		_rect.color = Color(colour.r, colour.g, colour.b, alpha)


func is_running() -> bool:
	return _running


func _run(colour: Color, from: float, to: float, seconds: float) -> Signal:
	_from = from
	_to = to
	_time = maxf(0.01, seconds)
	_clock = 0.0
	_running = true
	if _rect != null:
		_rect.color = Color(colour.r, colour.g, colour.b, from)
	return finished


func _process(delta: float) -> void:
	if not _running or _rect == null:
		return
	_clock += delta
	var t := clampf(_clock / _time, 0.0, 1.0)
	# Smoothstep rather than linear: a linear alpha ramp reads as a wipe, and
	# every one of these fades is meant to feel like an eye opening or closing.
	_rect.color.a = lerpf(_from, _to, smoothstep(0.0, 1.0, t))
	if t >= 1.0:
		_running = false
		finished.emit()
