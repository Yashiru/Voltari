class_name VltBattleState
extends RefCounted

## The whole battle at rest.
##
## Two sides, each with N slots. Two sides is not a simplification: Gen 4 has no
## free-for-all, and a four-trainer multi battle is still two sides of two slots
## (spec 03).
##
## Field scope lives here — conditions affecting both sides.
##
## Effect instances are not modelled yet. They attach to these same four scopes
## and arrive with the effect system (spec 06); adding them changes what the
## scopes hold, not the shape of the state.

const SIDE_COUNT: int = 2

var sides: Array[VltSide] = []
var weather: String = ""
var weather_turns: int = 0
var turn: int = 0

## Where the turn stopped, when it stopped. Part of the state rather than of the
## engine, so a battle stays serialisable mid-turn and the request/response
## cycle a network needs comes for free (decision 0012).
var awaiting_replacement: Array[VltSlotRef] = []


static func create(slots_per_side: int) -> VltBattleState:
	var state: VltBattleState = VltBattleState.new()
	for _i: int in range(SIDE_COUNT):
		state.sides.append(VltSide.create(slots_per_side))
	return state


func slots_per_side() -> int:
	return sides[0].slots.size()


func is_valid_ref(reference: VltSlotRef) -> bool:
	if reference == null:
		return false
	if reference.side < 0 or reference.side >= SIDE_COUNT:
		return false
	return reference.slot >= 0 and reference.slot < slots_per_side()


func slot_at(reference: VltSlotRef) -> VltSlot:
	assert(is_valid_ref(reference), "slot reference out of range: %s" % reference)
	return sides[reference.side].slots[reference.slot]


func creature_at(reference: VltSlotRef) -> VltBattleCreature:
	assert(is_valid_ref(reference), "slot reference out of range: %s" % reference)
	return sides[reference.side].creature_in(reference.slot)


## Every position on the field, in a fixed order: side 0 then side 1, slot order
## within each. Ordering never depends on iteration over an unordered
## collection, which is what makes determinism provable (spec 03).
func all_refs() -> Array[VltSlotRef]:
	var refs: Array[VltSlotRef] = []
	for side: int in range(SIDE_COUNT):
		for slot: int in range(slots_per_side()):
			refs.append(VltSlotRef.at(side, slot))
	return refs


func clone() -> VltBattleState:
	var copy: VltBattleState = VltBattleState.new()

	copy.sides = []
	for side: VltSide in sides:
		copy.sides.append(side.clone())

	copy.weather = weather
	copy.weather_turns = weather_turns
	copy.turn = turn

	copy.awaiting_replacement = []
	for reference: VltSlotRef in awaiting_replacement:
		copy.awaiting_replacement.append(VltSlotRef.at(reference.side, reference.slot))

	return copy


func to_dict() -> Dictionary:
	var serialised_sides: Array = []
	for side: VltSide in sides:
		serialised_sides.append(side.to_dict())

	var pending: Array = []
	for reference: VltSlotRef in awaiting_replacement:
		pending.append(reference.to_array())

	return {
		"sides": serialised_sides,
		"weather": weather,
		"weather_turns": weather_turns,
		"turn": turn,
		"awaiting_replacement": pending,
	}


static func from_dict(data: Dictionary) -> VltBattleState:
	var state: VltBattleState = VltBattleState.new()

	for entry: Variant in data["sides"]:
		state.sides.append(VltSide.from_dict(entry))

	state.weather = data["weather"]
	state.weather_turns = data["weather_turns"]
	state.turn = data["turn"]

	for entry: Variant in data["awaiting_replacement"]:
		state.awaiting_replacement.append(VltSlotRef.from_array(PackedInt32Array(entry)))

	return state
