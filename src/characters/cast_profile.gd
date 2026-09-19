class_name CastProfile
extends RefCounted
## The two characters.
##
## One of them walks the hall with the map and is on screen the whole time —
## that is the MAIN character, and it is the one you play. The other waits at
## the far end of the hall and lies in the bed at the start, and talks about
## the photographs — that is the SIDE character.
##
## So there are two things here and no more: `main` and `side`, each a whole
## FigureProfile with its own name, build and five colours. There is no
## separate "who do you play as" any more, because the main character IS the
## one you play; `swap()` exchanges the two if you want it the other way round.
##
## Everything downstream asks this object for `main_figure()` or
## `side_figure()`, so the gallery, the hospital room and the ending do not
## each need to know who is who. The one exception is the drawn embrace at the
## ending, which is a fixed pose with a skirted figure on the left, so it asks
## by BUILD rather than by role.
##
## Defaults: Victor is the main character, Chelsea the side one.
##
## Two places hold a cast, and the order matters:
##
##   1. Inside a settings file, where the author put it. Travels with the gift.
##   2. `user://cast.json`, this machine's own default, used when a settings
##      file carries no cast and as the starting point for a new one.

enum Role { MAIN, SIDE }

const PATH := "user://cast.json"
const SCHEMA := 2

const DEFAULT_MAIN_NAME := "Victor"
const DEFAULT_SIDE_NAME := "Chelsea"

const ROLE_NAMES := {
	Role.MAIN: "main",
	Role.SIDE: "side",
}

const ROLE_LABELS := {
	Role.MAIN: "Main character",
	Role.SIDE: "Side character",
}

var main: FigureProfile = FigureProfile.trousers_default(DEFAULT_MAIN_NAME)
var side: FigureProfile = FigureProfile.skirt_default(DEFAULT_SIDE_NAME)


static func create_default() -> CastProfile:
	var cast := CastProfile.new()
	cast.main = FigureProfile.trousers_default(DEFAULT_MAIN_NAME)
	cast.side = FigureProfile.skirt_default(DEFAULT_SIDE_NAME)
	return cast


# ------------------------------------------------------------------- access

func figure_for(role: Role) -> FigureProfile:
	return side if role == Role.SIDE else main


func other_than(role: Role) -> Role:
	return Role.MAIN if role == Role.SIDE else Role.SIDE


static func label_for(role: Role) -> String:
	return ROLE_LABELS.get(role, "Main character")


## The one who walks, holds the map and is on screen the whole time.
func main_figure() -> FigureProfile:
	return main


## The one who waits at the end of the hall, lies in the bed, and talks.
func side_figure() -> FigureProfile:
	return side


## The figure drawn with a skirt, for the embrace's left-hand slot — the drawn
## pose is fixed, so it is chosen by build and not by role. With both
## characters on the same build the main one takes the right-hand slot, which
## is the taller of the two.
func skirt_figure() -> FigureProfile:
	if side.form == PixelFigure.Build.SKIRT:
		return side
	if main.form == PixelFigure.Build.SKIRT:
		return main
	return side


func trousers_figure() -> FigureProfile:
	if main.form == PixelFigure.Build.TROUSERS:
		return main
	if side.form == PixelFigure.Build.TROUSERS:
		return side
	return main


## Exchange the two, so whoever was waiting now walks. Names and looks go with
## them: the point is to change which of these two people you are, not to
## rename them.
func swap() -> void:
	var was_main := main
	main = side
	side = was_main


## Names, with a fallback, because an empty name in a line of dialogue reads
## as a bug: "  , do you remember this one?"
func name_for(role: Role) -> String:
	var figure := figure_for(role)
	if not figure.display_name.strip_edges().is_empty():
		return figure.display_name.strip_edges()
	return DEFAULT_SIDE_NAME if role == Role.SIDE else DEFAULT_MAIN_NAME


func main_name() -> String:
	return name_for(Role.MAIN)


func side_name() -> String:
	return name_for(Role.SIDE)


# --------------------------------------------------------------- JSON / disk

func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA,
		"main": main.to_figure_dict(),
		"side": side.to_figure_dict(),
	}


## Permissive in the same way AlbumSchema is: every field falls back to the
## default for that half of the cast, so a partial or hand-edited file still
## produces two whole people.
##
## Schema 1 is also read. It had "wife", "husband" and a "player" saying which
## of the two you walked as — so whichever that was becomes the main character
## and the other becomes the side one, which is exactly what those two words
## meant.
static func from_dict(data: Dictionary) -> CastProfile:
	var cast := create_default()
	var schema := int(data.get("schema", 0))

	if schema == SCHEMA:
		cast.main = FigureProfile.from_figure_dict(
			AlbumSchema.sub_dict(data, "main"), cast.main)
		cast.side = FigureProfile.from_figure_dict(
			AlbumSchema.sub_dict(data, "side"), cast.side)
		return cast

	if schema == 1:
		var wife := FigureProfile.from_figure_dict(
			AlbumSchema.sub_dict(data, "wife"),
			FigureProfile.skirt_default(DEFAULT_SIDE_NAME))
		var husband := FigureProfile.from_figure_dict(
			AlbumSchema.sub_dict(data, "husband"),
			FigureProfile.trousers_default(DEFAULT_MAIN_NAME))
		if str(data.get("player", "")).to_lower() == "husband":
			cast.main = husband
			cast.side = wife
		else:
			cast.main = wife
			cast.side = husband
		CCLog.info("cast", "read a schema 1 cast: %s walks, %s waits"
			% [cast.main_name(), cast.side_name()])
		return cast

	# Anything else: refuse rather than guess, the same rule the album manifest
	# follows. A default cast is a fine outcome.
	return cast


## The cast a settings file carries, or this machine's own if it carries none.
static func for_album(album: AlbumSchema.Album) -> CastProfile:
	if album != null and album.has_cast():
		return from_dict(album.cast)
	return load_saved()


## Never fails. A missing, unreadable or unparseable file is the default cast,
## because the alternative is a player who cannot get into the game.
static func load_saved(path: String = PATH) -> CastProfile:
	if FileAccess.file_exists(path):
		var text := FileAccess.get_file_as_string(path)
		if not text.is_empty():
			var parsed: Variant = JSON.parse_string(text)
			if typeof(parsed) == TYPE_DICTIONARY:
				return from_dict(parsed)
			CCLog.warn("cast", "%s is not valid JSON; using the default" % path)
		return create_default()

	return _adopt_old_profile()


## One figure, saved by the build that only had one. It becomes the main
## character, so nobody loses the figure they already made.
static func _adopt_old_profile(
		old_path: String = FigureProfile.PATH) -> CastProfile:
	var cast := create_default()
	if not FileAccess.file_exists(old_path):
		return cast

	var old := FigureProfile.load_saved(old_path)
	cast.main.form = old.form
	cast.main.skin = old.skin
	cast.main.hair = old.hair
	cast.main.dress = old.dress
	cast.main.wrap = old.wrap
	cast.main.shoe = old.shoe
	if not old.display_name.strip_edges().is_empty():
		cast.main.display_name = old.display_name
	CCLog.info("cast", "adopted the figure from %s" % old_path)
	return cast


## Returns true when it actually wrote. Callers on web should follow with
## Platform.sync_user_fs() — the data layer stays free of the autoloads.
func save(path: String = PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		CCLog.error("cast", "cannot write %s (error %d)"
			% [path, FileAccess.get_open_error()])
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	CCLog.info("cast", "saved the cast to %s (%s walks, %s waits)"
		% [path, main_name(), side_name()])
	return true
