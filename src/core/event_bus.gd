extends Node
## Autoload: EventBus
##
## Cross-cutting signals. Exists so the HUD, curator and companion do not all
## need a reference to RoundController. Anything that fires here should be a
## fact about the world, not a request — requests go through direct calls.

# --- album lifecycle ---
signal album_loaded(album: RefCounted)          # AlbumSchema.Album
signal album_load_failed(problems: Array)       # Array[AlbumValidator.Problem]

# --- round lifecycle ---
signal round_started(photo_index: int)
signal photo_approached(photo_index: int)
## She walked away from a frame without engaging it. The HUD needs this to
## take its prompt down: approaching is an edge event on an Area3D and so is
## leaving, and without the second one the prompt stayed up for the rest of
## the hall while E did nothing.
signal photo_left(photo_index: int)
signal photo_examined(photo_index: int)
signal guess_submitted(photo_index: int)
signal round_scored(photo_index: int, breakdown: Dictionary)
signal photo_revealed(photo_index: int)
signal round_finished(photo_index: int)

# --- the hint economy. cost is a fraction of the round's score. ---
signal unblur_purchased(photo_index: int, new_tier: int, cost: float)
signal hint_purchased(photo_index: int, tier: int, cost: float)

# --- curator ---
signal curator_line_requested(text: String, mood: StringName)
signal curator_line_finished()

# --- session ---
signal session_completed(total_score: float)
signal ending_started()
## The hug is over and the hall has faded out. The results screen waits for
## this rather than for session_completed, so nothing lands on top of the
## ending (the game ends with the hug; the numbers come after).
signal ending_finished()
