class_name VltLogEvent
extends RefCounted

## One observable thing that happened, in resolution order.
##
## Three obligations, from spec 07, and each is load-bearing:
##
## - **Completeness.** Replaying the log onto the initial state must reproduce
##   the final state (invariant 8). So an event carries its RESULTING VALUES,
##   not deltas: replay assigns instead of recomputing, which removes a whole
##   class of drift between the log and the state it describes.
## - **No text.** Events carry identifiers. Localisation is L4 and lives nowhere
##   else, which is what stops English strings spreading through the engine.
## - **Visibility.** Filtering is not only dropping: an opponent sees a
##   percentage, not exact HP. `reduced()` returns that lesser form.

enum Visibility {
	## Everyone sees it unchanged.
	PUBLIC,
	## Only the side it belongs to sees it at all.
	OWNER_ONLY,
	## Everyone sees it; non-owners see `reduced()`.
	TRANSFORMED,
}

## Field-level events belong to no side.
const NO_SIDE: int = -1

var visibility: Visibility = Visibility.PUBLIC
var owner_side: int = NO_SIDE


## Stable identifier, used for serialisation and for the differential
## projection. Never displayed.
func kind() -> String:
	assert(false, "VltLogEvent is abstract")
	return ""


## Applies this event to a state. Informational events are legitimately no-ops;
## anything that changed state must implement it, or invariant 8 fails.
func apply(_state: VltBattleState) -> void:
	pass


## The lesser form shown to a viewer not entitled to the full one. Only
## TRANSFORMED events need to override it.
func reduced() -> VltLogEvent:
	return self


## Whether `side` is entitled to see this event, and in which form.
func visible_to(side: int) -> bool:
	if visibility == Visibility.OWNER_ONLY:
		return owner_side == NO_SIDE or owner_side == side
	return true


func for_viewer(side: int) -> VltLogEvent:
	if not visible_to(side):
		return null
	if visibility == Visibility.TRANSFORMED and owner_side != side:
		return reduced()
	return self


## The scale a viewer who is not entitled to exact health sees instead.
const REDUCED_SCALE: int = 100


## Health as a proportion of the maximum, out of REDUCED_SCALE.
##
## One definition, because there were already two — damage and heal each carried
## their own — and the AI's view needs a third (spec 12). A sliver never rounds
## to nothing: reading zero would say a creature is dead when it is not, and no
## consumer can recover from that.
static func scaled_health(value: int, max_hp: int) -> int:
	if value <= 0:
		return 0
	return maxi(1, value * REDUCED_SCALE / max_hp)


func to_dict() -> Dictionary:
	var data: Dictionary = _payload()
	data["kind"] = kind()
	data["visibility"] = visibility
	data["owner_side"] = owner_side
	return data


func _payload() -> Dictionary:
	return {}


func _read_common(data: Dictionary) -> void:
	visibility = data["visibility"]
	owner_side = data["owner_side"]
