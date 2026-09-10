extends GdUnitTestSuite

## Turning a log into something a player watches (spec 17, sections 2 to 4).
##
## The reader is tested against a stage that records instead of rendering, which
## is the whole reason a stage is an interface. Nothing here needs a frame.

const OURS: int = 0
const THEIRS: int = 1
const MOVE: String = "tackle"


## Writes down what it was asked to do, and takes no time doing it.
class Recorder:
	extends BattleStage

	var calls: PackedStringArray = PackedStringArray()
	var refreshes: int = 0
	var last: VltBattleView = null

	func play(at: VltSlotRef, slot: String) -> void:
		calls.append("play %s @%d,%d" % [slot, at.side, at.slot])

	func say(line: BattleLines.Line) -> void:
		calls.append("say " + line.key)

	func refresh(view: VltBattleView) -> void:
		refreshes += 1
		last = view


func _registry() -> VltEffectRegistry:
	var registry: VltEffectRegistry = VltEffectRegistry.new()
	registry.register(VltBurn.define())
	return registry


func _moves() -> Dictionary[String, VltMoveDefinition]:
	return {
		MOVE: VltMoveDefinition.create(
			MOVE, "normal", VltMoveDefinition.Category.PHYSICAL, 40,
			VltMoveDefinition.ALWAYS_HITS
		)
	}


func _creature(species: String) -> VltBattleCreature:
	var input: VltStatInput = VltStatInput.new()
	input.base = PackedInt32Array([120, 100, 90, 80, 70, 60])
	input.ivs = PackedInt32Array([31, 31, 31, 31, 31, 31])
	input.evs = PackedInt32Array([0, 0, 0, 0, 0, 0])
	input.level = 50

	var made: VltBattleCreature = VltBattleCreature.create(
		input, species, PackedStringArray(["normal"])
	)
	made.moves.append(VltMoveSlot.create(MOVE, 10))
	return made


func _battle() -> VltBattleState:
	var state: VltBattleState = VltBattleState.create(1)
	for side: int in range(VltBattleState.SIDE_COUNT):
		state.sides[side].party.append(_creature("placeholder_base"))
		state.sides[side].party.append(_creature("placeholder_evolved"))
		state.sides[side].slots[0].occupy(0)
	return state


func _reader(state: VltBattleState, onto: BattleStage) -> BattleLogReader:
	var registry: VltEffectRegistry = _registry()
	return BattleLogReader.new(
		VltBattleView.of(state, registry, OURS),
		onto,
		registry,
		_moves(),
		{},
		state.sides[OURS].party
	)


func _events(state: VltBattleState) -> Array[VltLogEvent]:
	var ours: VltSlotRef = VltSlotRef.at(OURS, 0)
	var theirs: VltSlotRef = VltSlotRef.at(THEIRS, 0)
	var victim: VltBattleCreature = state.creature_at(theirs)

	var events: Array[VltLogEvent] = [
		VltLogTurnStart.create(1),
		VltLogMoveUsed.create(ours, MOVE, 0, 9, theirs),
		VltLogEffectiveness.create(theirs, 1),
		VltLogDamage.create(theirs, 60, victim.max_hp() - 60, victim.max_hp()),
		VltLogFaint.create(theirs),
	]
	return events


# --- what it does with an event ----------------------------------------------


func test_it_plays_a_clip_then_redraws_then_speaks() -> void:
	# The order is the point. A clip that played before the view knew about it
	# would animate a bar that had not dropped yet.
	var recorder: Recorder = Recorder.new()
	var state: VltBattleState = _battle()
	var reader: BattleLogReader = _reader(state, recorder)

	await reader.one(VltLogMoveUsed.create(VltSlotRef.at(OURS, 0), MOVE, 0, 9, VltSlotRef.at(THEIRS, 0)))

	assert_array(recorder.calls).is_equal(["play attack_physical @0,0", "say battle.move_used"])
	assert_int(recorder.refreshes).is_equal(1)


func test_a_silent_event_still_redraws() -> void:
	# Damage says nothing and changes everything. A reader that only acted on
	# events with a sentence would never move a health bar.
	var recorder: Recorder = Recorder.new()
	var state: VltBattleState = _battle()
	var reader: BattleLogReader = _reader(state, recorder)

	await reader.one(VltLogDamage.create(VltSlotRef.at(THEIRS, 0), 60, 100, 175))

	assert_int(recorder.refreshes).is_equal(1)
	for call: String in recorder.calls:
		assert_bool(call.begins_with("say")).override_failure_message(
			"damage said something"
		).is_false()


func test_the_view_moves_before_the_stage_is_told() -> void:
	var recorder: Recorder = Recorder.new()
	var state: VltBattleState = _battle()
	var reader: BattleLogReader = _reader(state, recorder)

	await reader.one(VltLogDamage.create(VltSlotRef.at(THEIRS, 0), 60, 115, 175))

	assert_int(recorder.last.theirs[0].health).override_failure_message(
		"the stage was redrawn from a view that had not been advanced"
	).is_equal(65)


func test_it_plays_a_whole_log_in_order() -> void:
	var recorder: Recorder = Recorder.new()
	var state: VltBattleState = _battle()
	var reader: BattleLogReader = _reader(state, recorder)

	await reader.play(_events(state))

	assert_array(recorder.calls).is_equal(
		[
			"say battle.turn_start",
			"play attack_physical @0,0",
			"say battle.move_used",
			"say battle.effectiveness.super",
			"play hurt @1,0",
			"play faint @1,0",
			"say battle.faint",
		]
	)


# --- skipping is not a second path -------------------------------------------


## Takes time, the way a real stage does, and can be told to stop taking it.
class Paced:
	extends BattleStage

	var skip: bool = false
	var waits: int = 0

	func _wait() -> void:
		if skip:
			return
		waits += 1

	func play(_at: VltSlotRef, _slot: String) -> void:
		await _wait()

	func say(_line: BattleLines.Line) -> void:
		await _wait()

	func refresh(_view: VltBattleView) -> void:
		await _wait()

	func skipping() -> bool:
		return skip


func _played(skip: bool) -> String:
	var stage: Paced = Paced.new()
	stage.skip = skip
	var state: VltBattleState = _battle()
	var reader: BattleLogReader = _reader(state, stage)

	await reader.play(_events(state))
	return "%d/%d hp=%d fainted=%s turn=%d" % [
		reader.view.mine[0].health,
		reader.view.theirs[0].health,
		reader.view.mine[0].current_hp,
		reader.view.theirs[0].fainted,
		reader.view.turn,
	]


func test_skipping_and_watching_end_in_the_same_place() -> void:
	# Section 4's property, and the reason the reader has no skip flag: there is
	# one path, and skipping only changes how long the stage takes.
	var watched: String = await _played(false)
	var skipped: String = await _played(true)

	assert_str(skipped).override_failure_message(
		"a skipped battle ended somewhere a watched one did not"
	).is_equal(watched)


func test_skipping_drops_the_waiting_and_nothing_else() -> void:
	var slow: Paced = Paced.new()
	var fast: Paced = Paced.new()
	fast.skip = true

	var state: VltBattleState = _battle()
	await BattleLogReader.new(
		VltBattleView.of(state, _registry(), OURS), slow, _registry(), _moves()
	).play(_events(_battle()))
	await BattleLogReader.new(
		VltBattleView.of(state, _registry(), OURS), fast, _registry(), _moves()
	).play(_events(_battle()))

	assert_int(slow.waits).is_greater(0)
	assert_int(fast.waits).override_failure_message(
		"skipping still waited"
	).is_equal(0)


# --- an event it does not know -----------------------------------------------


func test_an_unknown_event_does_not_stop_the_battle() -> void:
	# A reader that failed here would make adding a mechanic a UI change, every
	# time. This one is a kind nothing has ever emitted.
	var recorder: Recorder = Recorder.new()
	var state: VltBattleState = _battle()
	var reader: BattleLogReader = _reader(state, recorder)

	await reader.play([_stranger(), VltLogFaint.create(VltSlotRef.at(THEIRS, 0))] as Array[VltLogEvent])

	assert_array(recorder.calls).contains(["say battle.faint"])


## A kind nothing has ever emitted. Invented here rather than borrowed, because
## every kind the core actually has is one the reader handles — which is the
## meta-test's whole point, and leaves this one with nothing real to use.
class Stranger:
	extends VltLogEvent

	func kind() -> String:
		return "invented_by_a_test"

	func apply(_state: VltBattleState) -> void:
		pass

	func _payload() -> Dictionary:
		return {}


func _stranger() -> VltLogEvent:
	var event: Stranger = Stranger.new()
	event.visibility = VltLogEvent.Visibility.PUBLIC
	return event
