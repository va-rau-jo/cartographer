class_name FigureProfile
extends RefCounted
## One character: a name, a build, and five colours.
##
## The brief asked for a customizable player model, and for a drawn figure that
## means one thing: the palette. Five colours — skin, hair, lower half, upper
## half, shoes — and PixelFigure derives every shade from them, so a single
## swatch moves the base tone and the form shading follows it (see
## Palette._shade).
##
## The build (PixelFigure.Build) says which of the two drawings this character
## uses: trousers and a short crop, or a skirt and a bun. It is a look, not a
## role — either character can be either build.
##
## The pair of them is CastProfile; this is one half of it.
##
## The colour slots keep their original names in code, because that is what
## PixelFigure's palette calls them, but they mean different garments on the
## two builds:
##
##     slot     skirt build        trousers build
##     dress    the dress          the trousers
##     wrap     the cardigan       the jumper

## The single-figure file this class used to own, kept only so a profile saved
## by an earlier build still means something. CastProfile reads it once, for
## the main character, when there is no cast file yet.
const PATH := "user://profile.json"
const SCHEMA := 1

## Presets, per slot. Swatches rather than a colour wheel: five wheels is a
## paint program, and the point is to look like someone in under a minute.
## Deliberately narrow ranges — these are an old couple's colours, not a
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
## Trousers and jumpers get their own ranges rather than borrowing the dress
## swatches: trousers in this room are greys, browns and a dark green, and
## offering a plum dress colour for them is offering nothing.
const TROUSERS := [
	Color(0.42, 0.40, 0.36), Color(0.31, 0.33, 0.38),
	Color(0.46, 0.38, 0.29), Color(0.34, 0.38, 0.33),
	Color(0.55, 0.52, 0.46), Color(0.24, 0.23, 0.22),
]
const JUMPERS := [
	Color(0.55, 0.45, 0.33), Color(0.36, 0.42, 0.50),
	Color(0.42, 0.48, 0.40), Color(0.60, 0.56, 0.44),
	Color(0.50, 0.36, 0.32), Color(0.70, 0.66, 0.58),
]
const SHOES := [
	Color(0.22, 0.18, 0.17), Color(0.34, 0.26, 0.20),
	Color(0.44, 0.40, 0.38), Color(0.28, 0.24, 0.30),
]

## How long a name may be. Long enough for anything anyone is called, short
## enough that it cannot push a line of dialogue off the screen.
const NAME_LIMIT := 24

var display_name: String = ""
## Which of the two drawings this character uses. See PixelFigure's canvases.
var form: PixelFigure.Build = PixelFigure.Build.SKIRT

var skin: Color = SKINS[1]
var hair: Color = HAIRS[1]
var dress: Color = DRESSES[0]
var wrap: Color = WRAPS[0]
var shoe: Color = SHOES[0]


## The skirt build as it starts: silver hair, a plum dress, a blue cardigan.
static func skirt_default(figure_name: String = "") -> FigureProfile:
	var p := FigureProfile.new()
	p.display_name = figure_name
	p.form = PixelFigure.Build.SKIRT
	p.skin = SKINS[1]
	p.hair = HAIRS[1]
	p.dress = DRESSES[0]
	p.wrap = WRAPS[0]
	p.shoe = SHOES[0]
	return p


## The trousers build as it starts. The same colours the second palette has
## always used in the hospital room and at the far end of the hall, so nothing
## about the scenes changes by moving them in here.
static func trousers_default(figure_name: String = "") -> FigureProfile:
	var p := FigureProfile.new()
	p.display_name = figure_name
	p.form = PixelFigure.Build.TROUSERS
	# Every one of these is a SWATCH, not a hand-picked colour near one. The
	# first version of this used the exact tones the old husband palette had,
	# and two of them were in no swatch list — so the characters screen opened
	# with nothing ringed in the skin and hair rows.
	p.skin = SKINS[1]
	p.hair = HAIRS[1]
	p.dress = TROUSERS[0]
	p.wrap = JUMPERS[0]
	p.shoe = SHOES[0]
	return p


## The swatches this figure should be offered for its lower-half slot.
func dress_options() -> Array:
	return TROUSERS if form == PixelFigure.Build.TROUSERS else DRESSES


func wrap_options() -> Array:
	return JUMPERS if form == PixelFigure.Build.TROUSERS else WRAPS


## What to call the lower-half slot on screen.
func dress_label() -> String:
	return "Trousers" if form == PixelFigure.Build.TROUSERS else "Dress"


## The build, as the one word the screen shows on its toggle.
func build_label() -> String:
	return "Trousers" if form == PixelFigure.Build.TROUSERS else "Skirt"


## Move this figure to the other build, taking its colours to that build's
## nearest swatch — a plum dress is not a colour trousers are offered in, and a
## figure whose colour is in no swatch opens the screen with nothing ringed.
func set_build(new_build: PixelFigure.Build) -> void:
	if form == new_build:
		return
	var dress_index := index_of(dress_options(), dress)
	var wrap_index := index_of(wrap_options(), wrap)
	form = new_build
	var dresses := dress_options()
	var wraps := wrap_options()
	dress = dresses[clampi(dress_index, 0, dresses.size() - 1)] \
		if dress_index >= 0 else dresses[0]
	wrap = wraps[clampi(wrap_index, 0, wraps.size() - 1)] \
		if wrap_index >= 0 else wraps[0]


func wrap_label() -> String:
	return "Jumper" if form == PixelFigure.Build.TROUSERS else "Cardigan"


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


## Colours and build only — the shape of the "figure" object inside both the
## old single-figure file and the current cast file.
func to_figure_dict() -> Dictionary:
	return {
		"name": display_name,
		"build": "trousers" if form == PixelFigure.Build.TROUSERS else "skirt",
		"skin": skin.to_html(false),
		"hair": hair.to_html(false),
		"dress": dress.to_html(false),
		"wrap": wrap.to_html(false),
		"shoe": shoe.to_html(false),
	}


## Read a figure object over the top of `onto` — which carries the defaults for
## whichever of the two this is, so a file that only recorded a hair colour
## still produces a whole person.
##
## "build" is the current key; "form" with "man"/"woman" is what the first
## version of this file wrote, and is still read so nobody's saved figure is
## lost.
static func from_figure_dict(data: Dictionary,
		onto: FigureProfile = null) -> FigureProfile:
	var profile := onto if onto != null else FigureProfile.new()

	var raw_name := str(data.get("name", profile.display_name)).strip_edges()
	if not raw_name.is_empty():
		profile.display_name = raw_name.substr(0, NAME_LIMIT)

	match str(data.get("build", data.get("form", ""))).to_lower():
		"trousers", "man": profile.form = PixelFigure.Build.TROUSERS
		"skirt", "woman": profile.form = PixelFigure.Build.SKIRT

	profile.skin = _colour(data, "skin", profile.skin)
	profile.hair = _colour(data, "hair", profile.hair)
	profile.dress = _colour(data, "dress", profile.dress)
	profile.wrap = _colour(data, "wrap", profile.wrap)
	profile.shoe = _colour(data, "shoe", profile.shoe)
	return profile


func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "figure": to_figure_dict()}


static func from_dict(data: Dictionary) -> FigureProfile:
	var profile := FigureProfile.new()
	if int(data.get("schema", 0)) != SCHEMA:
		# Same rule as the album manifest: refuse rather than guess. A default
		# figure is a fine outcome; a figure built from misread fields is not.
		return profile
	return from_figure_dict(data.get("figure", {}), profile)


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
