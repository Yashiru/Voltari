class_name VltTurnEngine
extends RefCounted

## Resolves one turn.
##
## `resolve(state, commands, decider)` is a pure function: the input state is
## deep-copied on entry and never touched (decision 0011). It returns either a
## finished turn, a request for input it could not have been given up front, or
## a rejection — an illegal command never produces a corrupted battle
## (decision 0013).
##
## The machine names no effect and branches on none. Where effects will
## intervene is VltTurnAnchor; nothing binds to those anchors yet, and the
## comments below mark where the queues will be drained.
##
## Not yet modelled, and each is an effect rather than a gap in the machine:
## weather damage modifiers, screens, paralysis speed, accuracy and evasion
## stages, secondary effects, residual damage.
##
## Replacement is requested at the end of the turn. Whether the oracle asks
## sooner is a fidelity question the battle differential will settle; it is
## recorded here rather than assumed correct.

const FIRST_DAMAGE_ROLL: int = 85
const CRITICAL_NUMERATOR: int = 1
const CRITICAL_DENOMINATOR: int = 16

var _moves: Dictionary[String, VltMoveDefinition] = {}
var _chart: VltTypeChart = null
var _effects: VltEffectRegistry = null


func _init(
	move_registry: Dictionary[String, VltMoveDefinition],
	chart: VltTypeChart,
	effects: VltEffectRegistry = null
) -> void:
	_moves = move_registry
	_chart = chart
	# An engine with no effects registered is a valid engine; it just has none.
	_effects = effects if effects != null else VltEffectRegistry.new()


# --- entry point ------------------------------------------------------------


func resolve(
	state: VltBattleState, commands: Array[VltCommand], decider: VltDecider
) -> VltTurnOutcome:
	if not state.awaiting_replacement.is_empty():
		return _resume(state, commands)

	var rejection: String = _validate(state, commands)
	if rejection != "":
		return VltTurnOutcome.rejected(rejection)

	var working: VltBattleState = state.clone()
	var log: VltBattleLog = VltBattleLog.new()

	# ANCHOR: TURN_START
	working.turn += 1
	log.append(VltLogTurnStart.create(working.turn))

	for command: VltCommand in _ordered(working, commands, decider):
		_run_action(working, command, decider, log)

	# ANCHOR: RESIDUAL
	VltEffectDispatch.run_triggers(
		working, _effects, VltTurnAnchor.Anchor.RESIDUAL, decider, log
	)
	_expire_effects(working)

	return _finish(working, log)


# --- validation -------------------------------------------------------------


## Returns an empty string when the commands are acceptable, otherwise the
## reason. Legality is not the same as game rules: no PP left will one day yield
## Struggle, which is a rule resolved during execution, not a rejection.
func _validate(state: VltBattleState, commands: Array[VltCommand]) -> String:
	var seen: Array[String] = []

	for command: VltCommand in commands:
		if not state.is_valid_ref(command.actor):
			return "actor %s is not a slot on this field" % command.actor

		var key: String = str(command.actor)
		if seen.has(key):
			return "two commands submitted for %s" % command.actor
		seen.append(key)

		var actor: VltBattleCreature = state.creature_at(command.actor)
		if actor == null:
			return "%s is empty" % command.actor

		var problem: String = (
			_validate_move(state, command, actor)
			if command.kind == VltCommand.Kind.MOVE
			else _validate_switch(state, command)
		)
		if problem != "":
			return problem

	return ""


func _validate_move(
	state: VltBattleState, command: VltCommand, actor: VltBattleCreature
) -> String:
	if command.move_index < 0 or command.move_index >= actor.moves.size():
		return "move index %d out of range for %s" % [command.move_index, command.actor]

	var slot: VltMoveSlot = actor.moves[command.move_index]
	if not _moves.has(slot.move_id):
		return "unknown move \"%s\"" % slot.move_id
	if slot.pp <= 0:
		return "no PP left for \"%s\"" % slot.move_id
	if not state.is_valid_ref(command.target):
		return "target %s is not a slot on this field" % command.target

	return ""


func _validate_switch(state: VltBattleState, command: VltCommand) -> String:
	var side: VltSide = state.sides[command.actor.side]

	if command.party_index < 0 or command.party_index >= side.party.size():
		return "party index %d out of range" % command.party_index
	if side.party[command.party_index].is_fainted():
		return "cannot switch to a fainted creature"

	for slot: VltSlot in side.slots:
		if slot.occupant == command.party_index:
			return "party member %d is already on the field" % command.party_index

	return ""


# --- ordering ---------------------------------------------------------------


## Order is computed once, after commands are locked (spec 04). Switches run
## before moves; moves go by priority, then speed, then an explicit tie.
func _ordered(
	state: VltBattleState, commands: Array[VltCommand], decider: VltDecider
) -> Array[VltCommand]:
	var switches: Array[VltCommand] = []
	var moves: Array[VltCommand] = []

	for command: VltCommand in commands:
		if command.kind == VltCommand.Kind.SWITCH:
			switches.append(command)
		else:
			moves.append(command)

	var ordered: Array[VltCommand] = []
	ordered.append_array(_by_slot(switches))
	ordered.append_array(_by_speed(state, moves, decider))
	return ordered


## Canonical order, used wherever nothing else decides: never iteration order
## over an unordered collection, which is what makes determinism provable.
func _by_slot(commands: Array[VltCommand]) -> Array[VltCommand]:
	var sorted: Array[VltCommand] = commands.duplicate()
	sorted.sort_custom(
		func(a: VltCommand, b: VltCommand) -> bool:
			if a.actor.side != b.actor.side:
				return a.actor.side < b.actor.side
			return a.actor.slot < b.actor.slot
	)
	return sorted


func _by_speed(
	state: VltBattleState, commands: Array[VltCommand], decider: VltDecider
) -> Array[VltCommand]:
	var sorted: Array[VltCommand] = _by_slot(commands)

	# Sorted on (priority, speed) only, with the canonical order above as the
	# stable base. Genuine ties are then broken by the decider, so the sort
	# itself never consults it — a comparator that did would make the number of
	# decisions depend on the sorting algorithm.
	sorted.sort_custom(
		func(a: VltCommand, b: VltCommand) -> bool:
			var priority_a: int = _priority_of(state, a)
			var priority_b: int = _priority_of(state, b)
			if priority_a != priority_b:
				return priority_a > priority_b
			return _speed_of(state, a.actor) > _speed_of(state, b.actor)
	)

	return _break_ties(state, sorted, decider)


## Exactly one decision per adjacent tied pair, whatever the outcomes, so the
## number of calls depends only on the shape of the turn.
func _break_ties(
	state: VltBattleState, sorted: Array[VltCommand], decider: VltDecider
) -> Array[VltCommand]:
	for index: int in range(1, sorted.size()):
		var earlier: VltCommand = sorted[index - 1]
		var later: VltCommand = sorted[index]

		var tied: bool = (
			_priority_of(state, earlier) == _priority_of(state, later)
			and _speed_of(state, earlier.actor) == _speed_of(state, later.actor)
		)
		if not tied:
			continue

		var winner: VltSlotRef = decider.speed_tie(earlier.actor, later.actor)
		if winner.equals(later.actor):
			sorted[index - 1] = later
			sorted[index] = earlier

	return sorted


func _priority_of(state: VltBattleState, command: VltCommand) -> int:
	var actor: VltBattleCreature = state.creature_at(command.actor)
	if actor == null:
		return 0
	var slot: VltMoveSlot = actor.moves[command.move_index]
	return _moves[slot.move_id].priority


func _speed_of(state: VltBattleState, reference: VltSlotRef) -> int:
	var creature: VltBattleCreature = state.creature_at(reference)
	if creature == null:
		return 0
	var stage: int = state.slot_at(reference).stat_stages[VltStats.Stat.SPE]
	return VltStats.apply_stage(creature.stats[VltStats.Stat.SPE], stage)


# --- execution --------------------------------------------------------------


func _run_action(
	state: VltBattleState, command: VltCommand, decider: VltDecider, log: VltBattleLog
) -> void:
	# ANCHOR: BEFORE_ACTION — sleep, flinch and confusion will be ordered
	# effects here, never branches in this method.
	var actor: VltBattleCreature = state.creature_at(command.actor)
	if actor == null or actor.is_fainted():
		return

	if command.kind == VltCommand.Kind.SWITCH:
		_run_switch(state, command, log)
	else:
		_run_move(state, command, decider, log)


func _run_switch(state: VltBattleState, command: VltCommand, log: VltBattleLog) -> void:
	# ANCHOR: SWITCH_OUT, then SWITCH_IN.
	var slot: VltSlot = state.slot_at(command.actor)
	log.append(VltLogSwitchOut.create(command.actor, slot.occupant))
	slot.vacate()
	slot.occupy(command.party_index)
	log.append(
		VltLogSwitchIn.create(
			command.actor, command.party_index, state.creature_at(command.actor).species_id
		)
	)


func _run_move(
	state: VltBattleState, command: VltCommand, decider: VltDecider, log: VltBattleLog
) -> void:
	var actor: VltBattleCreature = state.creature_at(command.actor)
	var move_slot: VltMoveSlot = actor.moves[command.move_index]
	var move: VltMoveDefinition = _moves[move_slot.move_id]

	move_slot.pp -= 1
	log.append(
		VltLogMoveUsed.create(
			command.actor, move.id, command.move_index, move_slot.pp, command.target
		)
	)

	var target: VltBattleCreature = state.creature_at(command.target)
	if target == null or target.is_fainted():
		log.append(VltLogMoveFailed.create(command.actor, VltLogMoveFailed.Reason.NO_TARGET))
		return

	# ANCHOR: MOVE_VETO. Type immunity is a veto rather than a zero multiplier,
	# which is the shape every registered veto takes too.
	if _chart.is_immune(move.type, target.types):
		log.append(VltLogMoveFailed.create(command.actor, VltLogMoveFailed.Reason.IMMUNE))
		return
	if VltEffectDispatch.is_vetoed(
		state, _effects, VltTurnAnchor.Anchor.MOVE_VETO, command.actor, command.target, move
	):
		log.append(VltLogMoveFailed.create(command.actor, VltLogMoveFailed.Reason.IMMUNE))
		return

	# ANCHOR: BEFORE_ACCURACY
	if move.accuracy != VltMoveDefinition.ALWAYS_HITS:
		if not decider.accuracy_check(move.accuracy):
			log.append(VltLogMoveFailed.create(command.actor, VltLogMoveFailed.Reason.MISSED))
			return

	if not move.is_damaging():
		return

	_deal_damage(state, command, move, decider, log)
	# ANCHOR: AFTER_HIT — contact, recoil and drain attach here.


func _deal_damage(
	state: VltBattleState,
	command: VltCommand,
	move: VltMoveDefinition,
	decider: VltDecider,
	log: VltBattleLog
) -> void:
	var actor: VltBattleCreature = state.creature_at(command.actor)
	var target: VltBattleCreature = state.creature_at(command.target)
	var exponent: int = _chart.exponent(move.type, target.types)

	var input: VltDamageInput = VltDamageInput.new()
	input.level = actor.level
	input.base_power = move.power
	input.attack = _offence(state, command.actor, move)
	input.defense = _defence(state, command.target, move)
	# Every stage ratio is contributed by effects. The engine does not know what
	# a burn or a screen is, and adding one changes nothing here (spec 06).
	input.modifiers = VltEffectDispatch.collect_modifiers(
		state, _effects, command.actor, command.target, move
	)
	input.is_critical = decider.critical_hit(CRITICAL_NUMERATOR, CRITICAL_DENOMINATOR)
	input.has_stab = actor.types.has(move.type)
	input.damage_roll = FIRST_DAMAGE_ROLL + decider.damage_roll()
	input.type_effectiveness_exponent = exponent

	var dealt: int = mini(VltDamage.compute(input), target.current_hp)

	log.append(VltLogEffectiveness.create(command.target, exponent))
	target.current_hp -= dealt
	log.append(
		VltLogDamage.create(command.target, dealt, target.current_hp, target.max_hp())
	)

	if target.is_fainted():
		# ANCHOR: ON_FAINT
		log.append(VltLogFaint.create(command.target))


func _offence(state: VltBattleState, reference: VltSlotRef, move: VltMoveDefinition) -> int:
	var physical: bool = move.category == VltMoveDefinition.Category.PHYSICAL
	var stat: int = VltStats.Stat.ATK if physical else VltStats.Stat.SPA
	return _stat_with_stage(state, reference, stat)


func _defence(state: VltBattleState, reference: VltSlotRef, move: VltMoveDefinition) -> int:
	var physical: bool = move.category == VltMoveDefinition.Category.PHYSICAL
	var stat: int = VltStats.Stat.DEF if physical else VltStats.Stat.SPD
	return _stat_with_stage(state, reference, stat)


func _stat_with_stage(state: VltBattleState, reference: VltSlotRef, stat: int) -> int:
	var creature: VltBattleCreature = state.creature_at(reference)
	var stage: int = state.slot_at(reference).stat_stages[stat]
	return VltStats.apply_stage(creature.stats[stat], stage)


# --- finishing and resuming -------------------------------------------------


## Drops effects whose duration ran out. Effects with no duration stay until
## something removes them.
func _expire_effects(state: VltBattleState) -> void:
	_drop_expired(state.effects)
	for side: VltSide in state.sides:
		_drop_expired(side.effects)
		for slot: VltSlot in side.slots:
			_drop_expired(slot.effects)
		for creature: VltBattleCreature in side.party:
			_drop_expired(creature.effects)


func _drop_expired(instances: Array[VltEffectInstance]) -> void:
	for index: int in range(instances.size() - 1, -1, -1):
		var instance: VltEffectInstance = instances[index]
		if instance.expires and instance.remaining <= 0:
			instances.remove_at(index)


func _finish(state: VltBattleState, log: VltBattleLog) -> VltTurnOutcome:
	var pending: Array[VltSlotRef] = _slots_needing_replacement(state)
	if not pending.is_empty():
		state.awaiting_replacement = pending
		return VltTurnOutcome.needs_input(state, log, pending)

	# ANCHOR: TURN_END
	return VltTurnOutcome.complete(state, log)


func _slots_needing_replacement(state: VltBattleState) -> Array[VltSlotRef]:
	var pending: Array[VltSlotRef] = []
	for reference: VltSlotRef in state.all_refs():
		var creature: VltBattleCreature = state.creature_at(reference)
		if creature != null and creature.is_fainted():
			if state.sides[reference.side].has_available_switch():
				pending.append(reference)
	return pending


## Answers a replacement request and finishes the turn. The commands must switch
## exactly the slots that were asked about — no more, no fewer.
func _resume(state: VltBattleState, commands: Array[VltCommand]) -> VltTurnOutcome:
	var expected: Array[VltSlotRef] = state.awaiting_replacement

	if commands.size() != expected.size():
		return VltTurnOutcome.rejected(
			"expected %d replacement(s), got %d" % [expected.size(), commands.size()]
		)

	for command: VltCommand in commands:
		if command.kind != VltCommand.Kind.SWITCH:
			return VltTurnOutcome.rejected("a replacement must be a switch")

		var matches: bool = false
		for reference: VltSlotRef in expected:
			if reference.equals(command.actor):
				matches = true
				break
		if not matches:
			return VltTurnOutcome.rejected("%s was not asked for a replacement" % command.actor)

		var problem: String = _validate_switch(state, command)
		if problem != "":
			return VltTurnOutcome.rejected(problem)

	var working: VltBattleState = state.clone()
	var log: VltBattleLog = VltBattleLog.new()

	for command: VltCommand in commands:
		var slot: VltSlot = working.slot_at(command.actor)
		slot.vacate()
		slot.occupy(command.party_index)
		log.append(
			VltLogSwitchIn.create(
				command.actor, command.party_index, working.creature_at(command.actor).species_id
			)
		)

	working.awaiting_replacement = []
	return _finish(working, log)
