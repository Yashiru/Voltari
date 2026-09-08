extends SceneTree

## Settles the question left open by decision 0011: should clone() be derived
## from a serialise round trip, so the two can never drift apart?
##
## Run: godot --headless --script tools/bench/state_copy_bench.gd
##
## The turn boundary copies the state once per turn, so the figure that matters
## is cost per copy, against the ten-second suite budget of spec 05.

const ITERATIONS: int = 5000
const PARTY_SIZE: int = 6
const MOVES_PER_CREATURE: int = 4
const SLOTS_PER_SIDE: int = 2


func _initialize() -> void:
	var state: VltBattleState = _battle()

	# One warm-up pass each, so neither mechanism pays for first-call overhead.
	state.clone()
	VltBattleState.from_dict(state.to_dict())

	var clone_usec: int = _time(state, true)
	var round_trip_usec: int = _time(state, false)

	print("battle state: 2 sides x %d creatures x %d moves, %d slots per side" % [
		PARTY_SIZE, MOVES_PER_CREATURE, SLOTS_PER_SIDE
	])
	print("iterations:   %d" % ITERATIONS)
	print("")
	_report("clone()", clone_usec)
	_report("from_dict(to_dict())", round_trip_usec)
	print("")
	print("round trip is %.2fx the cost of clone()" % (float(round_trip_usec) / float(clone_usec)))
	print("at one copy per turn, a 1000-turn fuzz run costs:")
	print("  clone()              %.1f ms" % (float(clone_usec) / ITERATIONS * 1000.0 / 1000.0))
	print("  from_dict(to_dict()) %.1f ms" % (float(round_trip_usec) / ITERATIONS * 1000.0 / 1000.0))

	quit()


func _report(label: String, total_usec: int) -> void:
	print("%-22s %7d us total   %8.3f us per copy" % [
		label, total_usec, float(total_usec) / ITERATIONS
	])


func _time(state: VltBattleState, use_clone: bool) -> int:
	var started: int = Time.get_ticks_usec()
	for _i: int in range(ITERATIONS):
		if use_clone:
			state.clone()
		else:
			VltBattleState.from_dict(state.to_dict())
	return Time.get_ticks_usec() - started


func _battle() -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(SLOTS_PER_SIDE)
	for side: int in range(VltBattleState.SIDE_COUNT):
		for index: int in range(PARTY_SIZE):
			state.sides[side].party.append(_creature("species_%d_%d" % [side, index]))
		for slot: int in range(SLOTS_PER_SIDE):
			state.sides[side].slots[slot].occupy(slot)
	return state


func _creature(species: String) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([100, 110, 90, 95, 85, 105])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([84, 84, 84, 0, 0, 0])
	input.level = 50
	input.nature_raised = VltStats.Stat.ATK
	input.nature_lowered = VltStats.Stat.SPA

	var creature: VltBattleCreature = VltBattleCreature.create(
		input, species, PackedStringArray(["water", "flying"])
	)
	for i: int in range(MOVES_PER_CREATURE):
		creature.moves.append(VltMoveSlot.create("move_%d" % i, 15))
	return creature
