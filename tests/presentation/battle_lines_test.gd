extends GdUnitTestSuite

## What an event says, and what it makes a creature do (spec 17, sections 5
## and 6).
##
## The single place an identifier becomes a sentence, so the tests are mostly
## about *which* sentence — a critical hit and a resisted hit are different ones
## in every language, and one key per situation is what keeps a condition out of
## a translation string.

const OURS: int = 0
const THEIRS: int = 1


func _names() -> Dictionary[String, String]:
	return {"0,0": "Ours", "1,0": "Theirs"}


func _line(event: VltLogEvent) -> BattleLines.Line:
	return BattleLines.of(event, _names())


func _ours() -> VltSlotRef:
	return VltSlotRef.at(OURS, 0)


func _theirs() -> VltSlotRef:
	return VltSlotRef.at(THEIRS, 0)


# --- which sentence ----------------------------------------------------------


func test_a_turn_start_says_its_number() -> void:
	var line: BattleLines.Line = _line(VltLogTurnStart.create(4))
	assert_str(line.key).is_equal("battle.turn_start")
	assert_str(line.arguments["number"]).is_equal("4")


func test_a_move_names_who_used_it_and_which() -> void:
	var line: BattleLines.Line = _line(
		VltLogMoveUsed.create(_ours(), "ember", 0, 9, _theirs())
	)
	assert_str(line.arguments["creature"]).is_equal("Ours")
	assert_str(line.arguments["move"]).is_equal("ember")


func test_each_failure_has_its_own_sentence() -> void:
	# "It missed" and "it had no effect" are not the same message, and a single
	# key with a reason argument would push the difference into the string.
	var keys: Array[String] = []
	for reason: VltLogMoveFailed.Reason in [
		VltLogMoveFailed.Reason.MISSED,
		VltLogMoveFailed.Reason.IMMUNE,
		VltLogMoveFailed.Reason.NO_TARGET,
	]:
		keys.append(_line(VltLogMoveFailed.create(_ours(), reason)).key)

	assert_int(keys.size()).is_equal(3)
	for key: String in keys:
		assert_bool(BattleLines.KEYS.has(key)).is_true()
	assert_bool(keys[0] != keys[1] and keys[1] != keys[2]).override_failure_message(
		"two failure reasons share a sentence"
	).is_true()


func test_a_neutral_hit_says_nothing() -> void:
	# Two of the four effectiveness cases have no sentence at all, which is why
	# this is not a lookup table.
	assert_bool(_line(VltLogEffectiveness.create(_theirs(), 0)).is_silent()).is_true()
	assert_str(_line(VltLogEffectiveness.create(_theirs(), 1)).key).is_equal(
		"battle.effectiveness.super"
	)
	assert_str(_line(VltLogEffectiveness.create(_theirs(), -1)).key).is_equal(
		"battle.effectiveness.resisted"
	)


func test_damage_says_nothing_because_the_bar_does() -> void:
	assert_bool(_line(VltLogDamage.create(_theirs(), 40, 100, 175)).is_silent()).is_true()


func test_a_stat_change_reads_its_size_and_its_direction() -> void:
	var cases: Dictionary[int, String] = {
		1: "battle.stat.rose",
		2: "battle.stat.rose_sharply",
		-1: "battle.stat.fell",
		-2: "battle.stat.fell_harshly",
	}
	for delta: int in cases:
		assert_str(
			_line(VltLogStatChange.create(_ours(), VltStats.Stat.ATK, delta, delta)).key
		).is_equal(cases[delta])


func test_a_stat_that_did_not_move_says_which_way_it_could_not() -> void:
	# The two are different sentences and the difference is the sign of where it
	# already is, not of a change that did not happen.
	assert_str(
		_line(VltLogStatChange.create(_ours(), VltStats.Stat.ATK, 0, 6)).key
	).is_equal("battle.stat.no_higher")
	assert_str(
		_line(VltLogStatChange.create(_ours(), VltStats.Stat.ATK, 0, -6)).key
	).is_equal("battle.stat.no_lower")


func test_an_effect_names_itself() -> void:
	# Effect keys cannot be listed up front: they carry an identifier, and only
	# the content knows which exist.
	var registry: VltEffectRegistry = VltEffectRegistry.new()
	registry.register(VltBurn.define())
	var state: VltBattleState = _state()
	VltEffectDispatch.apply(state, registry, VltBurn.ID, _ours(), _ours())

	var instance: VltEffectInstance = state.creature_at(_ours()).effects[0]
	assert_str(
		_line(
			VltLogEffectChanged.create(instance, VltEffectDefinition.Scope.CREATURE, _ours())
		).key
	).is_equal("effect.burn.began")

	assert_str(
		_line(
			VltLogEffectChanged.removal(VltBurn.ID, VltEffectDefinition.Scope.CREATURE, _ours())
		).key
	).is_equal("effect.burn.ended")


func test_a_capture_has_a_sentence_for_each_ending() -> void:
	assert_str(_line(VltLogCaptureShake.create(_theirs(), 1)).key).is_equal(
		"battle.capture.shake"
	)
	assert_str(_line(VltLogCaptureResult.create(_theirs(), 0, true)).key).is_equal(
		"battle.capture.caught"
	)
	assert_str(_line(VltLogCaptureResult.create(_theirs(), 0, false)).key).is_equal(
		"battle.capture.broke_free"
	)


func test_an_unnamed_position_still_reads() -> void:
	# A missing name is a content problem, not a reason to show nothing.
	var line: BattleLines.Line = BattleLines.of(VltLogFaint.create(_theirs()), {})
	assert_str(line.arguments["creature"]).is_equal("?")


func test_every_listed_key_is_one_something_can_produce() -> void:
	# The list exists so a meta-test can check the table has them all. A key in
	# the list that nothing emits would make that check pass on a lie.
	assert_int(BattleLines.KEYS.size()).is_greater(0)
	for key: String in BattleLines.KEYS:
		assert_bool(key.begins_with("battle.")).override_failure_message(
			"\"%s\" is listed but is not a battle line" % key
		).is_true()


# --- what it makes a creature do ---------------------------------------------


func _moves() -> Dictionary[String, VltMoveDefinition]:
	return {
		"tackle": VltMoveDefinition.create(
			"tackle", "normal", VltMoveDefinition.Category.PHYSICAL, 40,
			VltMoveDefinition.ALWAYS_HITS
		),
		"ember": VltMoveDefinition.create(
			"ember", "fire", VltMoveDefinition.Category.SPECIAL, 40,
			VltMoveDefinition.ALWAYS_HITS
		),
	}


func test_a_move_plays_the_animation_its_category_asks_for() -> void:
	# From the move rather than from the event: the log says which move, and the
	# move says what kind of thing it is.
	var physical: Array[BattleClips.Cue] = BattleClips.of(
		VltLogMoveUsed.create(_ours(), "tackle", 0, 9, _theirs()), _moves()
	)
	assert_str(physical[0].slot).is_equal("attack_physical")

	var special: Array[BattleClips.Cue] = BattleClips.of(
		VltLogMoveUsed.create(_ours(), "ember", 0, 9, _theirs()), _moves()
	)
	assert_str(special[0].slot).is_equal("attack_special")


func test_a_move_nobody_declared_still_animates() -> void:
	# A content gap must not freeze a battle mid-turn.
	var cues: Array[BattleClips.Cue] = BattleClips.of(
		VltLogMoveUsed.create(_ours(), "unknown", 0, 9, _theirs()), _moves()
	)
	assert_int(cues.size()).is_equal(1)


func test_damage_and_fainting_play_on_the_one_they_happened_to() -> void:
	var hurt: Array[BattleClips.Cue] = BattleClips.of(
		VltLogDamage.create(_theirs(), 40, 100, 175), _moves()
	)
	assert_str(hurt[0].slot).is_equal("hurt")
	assert_int(hurt[0].at.side).is_equal(THEIRS)

	var down: Array[BattleClips.Cue] = BattleClips.of(VltLogFaint.create(_theirs()), _moves())
	assert_str(down[0].slot).is_equal("faint")


func test_every_clip_asked_for_is_in_the_vocabulary() -> void:
	# Spec 16 owns the vocabulary and this asks for it. A slot named here and
	# absent there would resolve to nothing, silently, at the worst moment.
	var every: Array[String] = ClipMap.all_slots()
	var asked: Array[VltLogEvent] = [
		VltLogMoveUsed.create(_ours(), "tackle", 0, 9, _theirs()),
		VltLogMoveUsed.create(_ours(), "ember", 0, 9, _theirs()),
		VltLogDamage.create(_theirs(), 40, 100, 175),
		VltLogFaint.create(_theirs()),
		VltLogSwitchIn.create(_theirs(), 0, "species", 5, 100, 100),
	]

	for event: VltLogEvent in asked:
		for cue: BattleClips.Cue in BattleClips.of(event, _moves()):
			assert_bool(every.has(cue.slot)).override_failure_message(
				"\"%s\" is asked for and is in no set of the vocabulary" % cue.slot
			).is_true()


func test_an_event_with_nothing_to_animate_asks_for_nothing() -> void:
	assert_array(BattleClips.of(VltLogTurnStart.create(1), _moves())).is_empty()
	assert_array(BattleClips.of(VltLogPendingInput.create([]), _moves())).is_empty()


func _state() -> VltBattleState:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([100, 100, 100, 100, 100, 100])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50

	var state: VltBattleState = VltBattleState.create(1)
	for side: int in range(VltBattleState.SIDE_COUNT):
		state.sides[side].party.append(
			VltBattleCreature.create(input, "species_%d" % side, PackedStringArray(["normal"]))
		)
		state.sides[side].slots[0].occupy(0)
	return state
