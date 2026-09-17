extends Node
## Autoload: GameState
##
## The session's current shape. Only RoundController may write `phase`; every
## other system reads it. Keeping that rule is what stops the state machine
## from leaking into the HUD and the companion AI.

enum Phase {
	MENU,
	EDITOR,
	HOSPITAL,      ## opening scene, before the transition
	TRANSITION,    ## the dissolve into his mind
	GALLERY_IDLE,  ## walking the hall, no photo engaged
	APPROACH,
	EXAMINE,
	GUESSING,
	SUBMITTED,
	SCORED,
	REVEALED,
	REFLECT,
	ENDING,
}

var phase: Phase = Phase.MENU

## Index into the album's hung order, not into `photos`.
var current_photo_index: int = -1

## Per-photo round records, parallel to hung order. Each entry is the
## breakdown Dictionary from Scoring.score_round(), or null if not yet played.
var results: Array = []

## Unblur tier reached per photo (0 = untouched, 4 = fully revealed).
var unblur_tiers: Array[int] = []
## Hint tiers taken per photo, as Array[Array].
var hints_taken: Array = []

## Accumulated across the ten rounds; drives how dim the hall gets (plan §8.2).
var total_hints_taken: int = 0


func reset_for_album(photo_count: int) -> void:
	current_photo_index = -1
	total_hints_taken = 0
	results = []
	unblur_tiers = []
	hints_taken = []
	for _i in photo_count:
		results.append(null)
		unblur_tiers.append(0)
		hints_taken.append([])
	CCLog.info("state", "reset for %d photos" % photo_count)


func total_score() -> float:
	var sum := 0.0
	for r in results:
		if r != null:
			sum += float(r.get("total_score", 0.0))
	return sum


func photos_played() -> int:
	var n := 0
	for r in results:
		if r != null:
			n += 1
	return n


func is_played(index: int) -> bool:
	return index >= 0 and index < results.size() and results[index] != null


## 0.0 when she needed no help at all, 1.0 when she leaned on him constantly.
## The gallery's light level is driven from this.
func reliance() -> float:
	var played := photos_played()
	if played == 0:
		return 0.0
	# Three hints per photo is total reliance.
	return clampf(float(total_hints_taken) / float(played * 3), 0.0, 1.0)
