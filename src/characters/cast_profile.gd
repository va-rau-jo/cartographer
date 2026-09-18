class_name CastProfile
extends RefCounted
## The two of them, and which one you play.
##
## The game was written for one of them: she walks the hall, he waits at the end
## of it and talks about the photographs. Either half of that can now be either
## of them. Nothing in the fiction changes — one of them is dying and the other
## has come into their mind — only which one holds the map.
##
## So there are three things here and no more:
##
##   * `wife` and `husband`, each a whole FigureProfile with its own name,
##     build and five colours.
##   * `player`, which of the two the player walks as.
##
## Everything downstream asks this object the SAME two questions regardless of
## the answer — `player_figure()` and `companion_figure()` — so the gallery, the
## hospital room and the ending do not each need to know who is who. The one
## exception is the embrace at the ending, which is drawn as a specific pose of
## a specific pair and so asks for the wife and the husband by name.
##
## Defaults: she is the player and she is called Chelsea; he waits, and he is
## called Victor. A gift has an author and a recipient, and those are theirs.
##
## Saved to `user://cast.json`. A `user://profile.json` written by an earlier
## build — which knew only one figure — is adopted once, as the wife, so
## nobody loses the figure they already made.

enum Role { WIFE, HUSBAND }

const PATH := "user://cast.json"
const SCHEMA := 1

const DEFAULT_WIFE_NAME := "Chelsea"
const DEFAULT_HUSBAND_NAME := "Victor"

const ROLE_NAMES := {
	Role.WIFE: "wife",
	Role.HUSBAND: "husband",
}

var wife: FigureProfile = FigureProfile.wife_default(DEFAULT_WIFE_NAME)
var husband: FigureProfile = FigureProfile.husband_default(DEFAULT_HUSBAND_NAME)
var player: Role = Role.WIFE


static func create_default() -> CastProfile:
	var cast := CastProfile.new()
	cast.wife = FigureProfile.wife_default(DEFAULT_WIFE_NAME)
	cast.husband = FigureProfile.husband_default(DEFAULT_HUSBAND_NAME)
	cast.player = Role.WIFE
	return cast


# ------------------------------------------------------------------- access

func figure_for(role: Role) -> FigureProfile:
	return husband if role == Role.HUSBAND else wife


func other_than(role: Role) -> Role:
	return Role.WIFE if role == Role.HUSBAND else Role.HUSBAND


## The one who walks, holds the map and is on screen the whole time.
func player_figure() -> FigureProfile:
	return figure_for(player)


## The one who waits at the end of the hall, lies in the bed, and talks.
func companion_figure() -> FigureProfile:
	return figure_for(other_than(player))


func companion_role() -> Role:
	return other_than(player)


## Names, with a fallback, because an empty name in a line of dialogue reads
## as a bug: "  , do you remember this one?"
func name_for(role: Role) -> String:
	var figure := figure_for(role)
	if not figure.display_name.strip_edges().is_empty():
		return figure.display_name.strip_edges()
	return DEFAULT_HUSBAND_NAME if role == Role.HUSBAND else DEFAULT_WIFE_NAME


func player_name() -> String:
	return name_for(player)


func companion_name() -> String:
	return name_for(companion_role())


# --------------------------------------------------------------- JSON / disk

func to_dict() -> Dictionary:
	return {
		"schema": SCHEMA,
		"player": ROLE_NAMES.get(player, "wife"),
		"wife": wife.to_figure_dict(),
		"husband": husband.to_figure_dict(),
	}


## Permissive in the same way AlbumSchema is: every field falls back to the
## default for that half of the cast, so a partial or hand-edited file still
## produces two whole people.
static func from_dict(data: Dictionary) -> CastProfile:
	var cast := create_default()
	if int(data.get("schema", 0)) != SCHEMA:
		return cast

	cast.wife = FigureProfile.from_figure_dict(data.get("wife", {}), cast.wife)
	cast.husband = FigureProfile.from_figure_dict(
		data.get("husband", {}), cast.husband)

	# The builds are not the player's to swap: "wife" is drawn as a woman and
	# "husband" as a man, and a file claiming otherwise would put a skirt on
	# the figure the hospital room lies in the bed.
	cast.wife.form = PixelFigure.Form.WOMAN
	cast.husband.form = PixelFigure.Form.MAN

	if str(data.get("player", "")).to_lower() == "husband":
		cast.player = Role.HUSBAND
	return cast


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


## One figure, saved by the build that only had one. It was always her, so she
## keeps her colours and he starts from the default.
static func _adopt_old_profile(
		old_path: String = FigureProfile.PATH) -> CastProfile:
	var cast := create_default()
	if not FileAccess.file_exists(old_path):
		return cast

	var old := FigureProfile.load_saved(old_path)
	cast.wife.skin = old.skin
	cast.wife.hair = old.hair
	cast.wife.dress = old.dress
	cast.wife.wrap = old.wrap
	cast.wife.shoe = old.shoe
	if not old.display_name.strip_edges().is_empty():
		cast.wife.display_name = old.display_name
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
	CCLog.info("cast", "saved the cast to %s (playing as %s)"
		% [path, ROLE_NAMES.get(player, "wife")])
	return true
