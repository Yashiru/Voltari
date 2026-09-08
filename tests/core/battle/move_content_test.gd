extends GdUnitTestSuite

## The authored move roster, loaded and played.
##
## The build validates the YAML; this checks the payload survives the crossing
## into the engine and that every declared move actually works in a turn. A
## move that loads but cannot be used is content that only looks present.

const MOVES_PAYLOAD: String = "res://content/generated/moves.json"
const CHART_PAYLOAD: String = "res://content/generated/type-chart.json"

var _registry: Dictionary[String, VltMoveDefinition]
var _chart: VltTypeChart
var _engine: VltTurnEngine


func before() -> void:
	_registry = VltMoveRegistryLoader.from_payload(_read_json(MOVES_PAYLOAD))
	_chart = VltTypeChartLoader.from_payload(_read_json(CHART_PAYLOAD))
	_engine = VltTurnEngine.new(_registry, _chart)


@warning_ignore_start("unsafe_cast")
func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(file).override_failure_message(
		"missing %s — run `npm --prefix tools run content:build`" % path
	).is_not_null()
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text) as Dictionary
@warning_ignore_restore("unsafe_cast")


func _creature(types: PackedStringArray, move_ids: Array[String]) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([120, 100, 100, 100, 100, 100])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50

	var creature: VltBattleCreature = VltBattleCreature.create(input, "anonymous", types)
	for id: String in move_ids:
		creature.moves.append(VltMoveSlot.create(id, _registry[id].max_pp))
	return creature


func _battle(move_ids: Array[String], defender_types: PackedStringArray) -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(1)
	state.sides[0].party.append(_creature(PackedStringArray(["normal"]), move_ids))
	state.sides[1].party.append(_creature(defender_types, move_ids))
	for side: int in range(VltBattleState.SIDE_COUNT):
		state.sides[side].slots[0].occupy(0)
	return state


func _scripted() -> VltScriptedDecider:
	var decider: VltScriptedDecider = VltScriptedDecider.new()
	decider.damage_roll_index = 15
	decider.accuracy = VltScriptedDecider.Answer.ALWAYS
	decider.critical = VltScriptedDecider.Answer.NEVER
	return decider


func test_the_authored_roster_loads() -> void:
	assert_int(_registry.size()).is_greater(0)
	for id: String in _registry.keys():
		var move: VltMoveDefinition = _registry[id]
		assert_str(move.id).is_equal(id)
		assert_int(move.max_pp).is_greater(0)


func test_every_move_type_exists_in_the_type_chart() -> void:
	# Content cross-check: a move naming a type nobody declared would deal
	# neutral damage to everything and look entirely normal doing it.
	var known: PackedStringArray = _chart.known_types()
	for id: String in _registry.keys():
		assert_bool(known.has(_registry[id].type)).override_failure_message(
			"move \"%s\" has type \"%s\", which the chart does not declare" % [id, _registry[id].type]
		).is_true()


func test_every_declared_move_can_actually_be_used() -> void:
	# A move that loads but cannot be played is content that only looks present.
	for id: String in _registry.keys():
		var ids: Array[String] = [id]
		var state: VltBattleState = _battle(ids, PackedStringArray(["normal"]))
		var command: VltCommand = VltCommand.use_move(
			VltSlotRef.at(0, 0), 0, VltSlotRef.at(1, 0)
		)
		var outcome: VltTurnOutcome = _engine.resolve(state, [command], _scripted())

		assert_int(outcome.status).override_failure_message(
			"move \"%s\" was rejected: %s" % [id, outcome.rejection]
		).is_not_equal(VltTurnOutcome.Status.REJECTED)

		var used: bool = false
		for event: VltLogEvent in outcome.log.events:
			if event.kind() == VltLogMoveUsed.KIND:
				used = true
		assert_bool(used).override_failure_message("move \"%s\" produced no move event" % id).is_true()


func test_a_move_is_damaging_only_when_offensive_and_powered() -> void:
	# Two conditions, and each has to hold on its own. A status move that
	# declares power and an offensive move that declares none are both
	# non-damaging, and nothing said so.
	var offensive: VltMoveDefinition = VltMoveDefinition.create(
		"probe_offensive", "normal", VltMoveDefinition.Category.PHYSICAL, 40, 100
	)
	assert_bool(offensive.is_damaging()).is_true()

	var powerless: VltMoveDefinition = VltMoveDefinition.create(
		"probe_powerless", "normal", VltMoveDefinition.Category.PHYSICAL, 0, 100
	)
	assert_bool(powerless.is_damaging()).override_failure_message(
		"an offensive move with no power deals no damage"
	).is_false()

	var powered_status: VltMoveDefinition = VltMoveDefinition.create(
		"probe_status", "normal", VltMoveDefinition.Category.STATUS, 40, 100
	)
	assert_bool(powered_status.is_damaging()).override_failure_message(
		"a status move is never damaging, whatever power it carries"
	).is_false()


func test_a_status_move_deals_no_damage() -> void:
	var ids: Array[String] = ["inert_status"]
	var state: VltBattleState = _battle(ids, PackedStringArray(["normal"]))
	var command: VltCommand = VltCommand.use_move(VltSlotRef.at(0, 0), 0, VltSlotRef.at(1, 0))
	var outcome: VltTurnOutcome = _engine.resolve(state, [command], _scripted())

	for event: VltLogEvent in outcome.log.events:
		assert_str(event.kind()).is_not_equal(VltLogDamage.KIND)


func test_an_unerring_move_hits_even_when_accuracy_always_fails() -> void:
	# `always` is not 100: one skips the check, the other consults the decider.
	var decider: VltScriptedDecider = _scripted()
	decider.accuracy = VltScriptedDecider.Answer.NEVER

	var unerring: Array[String] = ["unerring_physical"]
	var rolled: Array[String] = ["heavy_physical"]

	var hit_state: VltBattleState = _battle(unerring, PackedStringArray(["normal"]))
	var hit: VltTurnOutcome = _engine.resolve(
		hit_state, [VltCommand.use_move(VltSlotRef.at(0, 0), 0, VltSlotRef.at(1, 0))], decider
	)
	assert_bool(_has_kind(hit.log, VltLogDamage.KIND)).is_true()

	var miss_state: VltBattleState = _battle(rolled, PackedStringArray(["normal"]))
	var missed: VltTurnOutcome = _engine.resolve(
		miss_state, [VltCommand.use_move(VltSlotRef.at(0, 0), 0, VltSlotRef.at(1, 0))], decider
	)
	assert_bool(_has_kind(missed.log, VltLogDamage.KIND)).is_false()
	assert_bool(_has_kind(missed.log, VltLogMoveFailed.KIND)).is_true()


func test_an_immune_defender_blocks_an_authored_move() -> void:
	var ids: Array[String] = ["ground_physical"]
	var state: VltBattleState = _battle(ids, PackedStringArray(["flying"]))
	var outcome: VltTurnOutcome = _engine.resolve(
		state, [VltCommand.use_move(VltSlotRef.at(0, 0), 0, VltSlotRef.at(1, 0))], _scripted()
	)

	assert_bool(_has_kind(outcome.log, VltLogDamage.KIND)).is_false()
	assert_bool(_has_kind(outcome.log, VltLogMoveFailed.KIND)).is_true()


func test_priority_is_carried_from_the_content() -> void:
	var ids: Array[String] = ["priority_physical", "basic_physical"]
	var state: VltBattleState = _battle(ids, PackedStringArray(["normal"]))
	# Side 1 is made faster, so only the priority move can act first.
	state.sides[1].party[0].stats[VltStats.Stat.SPE] = 999

	var commands: Array[VltCommand] = [
		VltCommand.use_move(VltSlotRef.at(0, 0), 0, VltSlotRef.at(1, 0)),
		VltCommand.use_move(VltSlotRef.at(1, 0), 1, VltSlotRef.at(0, 0)),
	]
	var outcome: VltTurnOutcome = _engine.resolve(state, commands, _scripted())

	for event: VltLogEvent in outcome.log.events:
		if event.kind() == VltLogMoveUsed.KIND:
			assert_int((event as VltLogMoveUsed).actor.side).is_equal(0)
			return
	fail("no move was used")


func _has_kind(log: VltBattleLog, kind: String) -> bool:
	for event: VltLogEvent in log.events:
		if event.kind() == kind:
			return true
	return false
