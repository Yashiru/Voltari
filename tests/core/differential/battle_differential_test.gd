extends GdUnitTestSuite

## The battle differential (decision 0009).
##
## Procedure vectors assert formulas; this asserts ORDER. Both engines are
## driven by the same decision policy — they share answers, never random
## numbers — and their logs are compared through a shared projection.
##
## Voltari events with no oracle counterpart, and why they are dropped:
##   turn_start   the oracle's `|turn|` marker is compared through the state
##   switch_out   the oracle emits only the incoming switch
##   move_failed  no failing scenario is covered yet
## An event dropped without a reason is a hole in the differential, so the list
## lives here rather than in the projection code.

const VECTORS: String = "res://tests/fixtures/oracle/battle/scripted.json"
const CHART_PAYLOAD: String = "res://content/generated/type-chart.json"

var _chart: VltTypeChart
var _effects: VltEffectRegistry


func before() -> void:
	_chart = VltTypeChartLoader.from_payload(_read_json(CHART_PAYLOAD))
	_effects = VltEffectRegistry.new()
	_effects.register(VltBurn.define())
	_effects.register(VltReflect.define())


@warning_ignore_start("unsafe_cast")
func _read_json(path: String) -> Dictionary:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	assert_object(file).override_failure_message("missing %s" % path).is_not_null()
	var text: String = file.get_as_text()
	file.close()
	return JSON.parse_string(text) as Dictionary


func _list(source: Dictionary, key: String) -> Array:
	return source[key] as Array


func _dict(value: Variant) -> Dictionary:
	return value as Dictionary


func _array(value: Variant) -> Array:
	return value as Array


func _num(value: Variant) -> int:
	return int(value as float)


func _text(value: Variant) -> String:
	return value as String
@warning_ignore_restore("unsafe_cast")


func _ints(values: Array) -> PackedInt32Array:
	var result: PackedInt32Array = PackedInt32Array()
	for value: Variant in values:
		result.append(_num(value))
	return result


func _strings(values: Array) -> PackedStringArray:
	var result: PackedStringArray = PackedStringArray()
	for value: Variant in values:
		result.append(_text(value))
	return result


func _category(name: String) -> VltMoveDefinition.Category:
	if name == "special":
		return VltMoveDefinition.Category.SPECIAL
	if name == "status":
		return VltMoveDefinition.Category.STATUS
	return VltMoveDefinition.Category.PHYSICAL


## Builds the battle and the move registry from the recorded numbers. The
## creature the oracle used is irrelevant: only its statistics crossed over.
func _setup(vector: Dictionary) -> Array:
	var state: VltBattleState = VltBattleState.create(1)
	var registry: Dictionary[String, VltMoveDefinition] = {}
	var parties: Array = _list(vector, "parties")

	for side: int in range(VltBattleState.SIDE_COUNT):
		for entry: Variant in _array(parties[side]):
			var member: Dictionary = _dict(entry)

			var input: VltStatInput = VltStatInput.new()
			input.level = _num(member["level"])
			input.base = _ints(_array(member["base"]))
			input.ivs = _ints(_array(member["ivs"]))
			input.evs = _ints(_array(member["evs"]))

			var creature: VltBattleCreature = VltBattleCreature.create(
				input, "anonymous", _strings(_array(member["types"]))
			)

			# The oracle's derived stats must match ours, or the comparison is
			# measuring stat derivation rather than resolution order.
			var expected_stats: PackedInt32Array = _ints(_array(member["stats"]))
			assert_array(creature.stats).override_failure_message(
				"derived stats differ from the oracle's"
			).is_equal(expected_stats)

			for move_entry: Variant in _array(member["moves"]):
				var move: Dictionary = _dict(move_entry)
				var id: String = _text(move["id"])
				registry[id] = VltMoveDefinition.create(
					id,
					_text(move["type"]),
					_category(_text(move["category"])),
					_num(move["power"]),
					_num(move["accuracy"]),
					_num(move["priority"]),
					_num(move["pp"])
				)
				creature.moves.append(VltMoveSlot.create(id, _num(move["pp"])))

			state.sides[side].party.append(creature)

		state.sides[side].slots[0].occupy(0)

	# Conditions the oracle set up before its script ran. The generator recorded
	# them in Voltari vocabulary; the mapping stayed on the tooling side.
	for entry: Variant in _list(vector, "conditions"):
		var condition: Dictionary = _dict(entry)
		var at: VltSlotRef = VltSlotRef.at(_num(condition["side"]), _num(condition["slot"]))
		var applied: bool = VltEffectDispatch.apply(
			state, _effects, _text(condition["effect"]), at, null
		)
		assert_bool(applied).override_failure_message(
			"could not apply the recorded condition"
		).is_true()

	return [state, registry]


func _decider(policy: Dictionary) -> VltScriptedDecider:
	var decider: VltScriptedDecider = VltScriptedDecider.new()
	decider.damage_roll_index = _num(policy["damage_roll_index"])
	decider.accuracy = (
		VltScriptedDecider.Answer.ALWAYS
		if _text(policy["accuracy"]) == "always"
		else VltScriptedDecider.Answer.NEVER
	)
	decider.critical = (
		VltScriptedDecider.Answer.ALWAYS
		if _text(policy["critical"]) == "always"
		else VltScriptedDecider.Answer.NEVER
	)
	decider.speed_tie_winner_side = _num(policy["speed_tie_winner_side"])
	return decider


func _commands_for(turn: Array, state: VltBattleState) -> Array[VltCommand]:
	var commands: Array[VltCommand] = []
	for side: int in range(turn.size()):
		var entry: Dictionary = _dict(turn[side])
		var actor: VltSlotRef = VltSlotRef.at(side, 0)
		if _text(entry["kind"]) == "switch":
			commands.append(VltCommand.switch_to(actor, _num(entry["party"])))
		else:
			commands.append(
				VltCommand.use_move(actor, _num(entry["index"]), VltSlotRef.at(1 - side, 0))
			)
	return commands


## Projects a Voltari log into the shared vocabulary.
func _project(log: VltBattleLog) -> Array:
	var projected: Array = []

	for event: VltLogEvent in log.events:
		match event.kind():
			VltLogMoveUsed.KIND:
				var used: VltLogMoveUsed = event as VltLogMoveUsed
				projected.append({
					"kind": "move",
					"side": used.actor.side,
					"slot": used.actor.slot,
					"move_index": used.move_index,
				})
			VltLogEffectiveness.KIND:
				var effect: VltLogEffectiveness = event as VltLogEffectiveness
				# The oracle says nothing when a hit is neutral, so neither do we.
				if effect.exponent != 0:
					projected.append({
						"kind": "effectiveness",
						"side": effect.target.side,
						"slot": effect.target.slot,
						"level": "super" if effect.exponent > 0 else "resisted",
					})
			VltLogDamage.KIND:
				var hit: VltLogDamage = event as VltLogDamage
				projected.append({
					"kind": "damage",
					"side": hit.target.side,
					"slot": hit.target.slot,
					"hp_after": hit.current_hp,
				})
			VltLogHeal.KIND:
				var healed: VltLogHeal = event as VltLogHeal
				projected.append({
					"kind": "heal",
					"side": healed.target.side,
					"slot": healed.target.slot,
					"hp_after": healed.current_hp,
				})
			VltLogFaint.KIND:
				var down: VltLogFaint = event as VltLogFaint
				projected.append({"kind": "faint", "side": down.target.side, "slot": down.target.slot})
			VltLogSwitchIn.KIND:
				var arrival: VltLogSwitchIn = event as VltLogSwitchIn
				projected.append({
					"kind": "switch", "side": arrival.target.side, "slot": arrival.target.slot
				})

	return projected


func _describe(events: Array) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for entry: Variant in events:
		var event: Dictionary = _dict(entry)
		var label: String = "%s(%d,%d" % [_text(event["kind"]), _num(event["side"]), _num(event["slot"])]
		if event.has("hp_after"):
			label += " hp=%d" % _num(event["hp_after"])
		if event.has("move_index"):
			label += " move=%d" % _num(event["move_index"])
		if event.has("level"):
			label += " %s" % _text(event["level"])
		parts.append(label + ")")
	return "\n  ".join(parts)


func test_every_scripted_battle_matches_the_oracle() -> void:
	var vectors: Array = _list(_read_json(VECTORS), "vectors")
	assert_int(vectors.size()).is_greater(0)

	for entry: Variant in vectors:
		var vector: Dictionary = _dict(entry)
		var built: Array = _setup(vector)
		var state: VltBattleState = built[0]
		var registry: Dictionary[String, VltMoveDefinition] = built[1]

		var engine: VltTurnEngine = VltTurnEngine.new(registry, _chart, _effects)
		var decider: VltScriptedDecider = _decider(_dict(vector["policy"]))
		var produced: Array = []

		for turn_entry: Variant in _list(vector, "script"):
			var outcome: VltTurnOutcome = engine.resolve(
				state, _commands_for(_array(turn_entry), state), decider
			)
			if outcome.status == VltTurnOutcome.Status.REJECTED:
				break
			produced.append_array(_project(outcome.log))
			state = outcome.state
			# A battle that stops for a replacement ends the comparison here:
			# the oracle's replacement timing is still an open question (spec 04).
			if outcome.status == VltTurnOutcome.Status.NEEDS_INPUT:
				break

		var expected: Array = _list(vector, "expected")
		assert_str(_describe(produced)).override_failure_message(
			"%s\n\nexpected:\n  %s\n\ngot:\n  %s"
			% [_text(vector["id"]), _describe(expected), _describe(produced)]
		).is_equal(_describe(expected))
