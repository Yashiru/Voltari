class_name VltEffectDispatch
extends RefCounted

## Collects the effects active at an anchor and runs them in order.
##
## Ordering, from spec 06:
##   1. declared priority, higher first
##   2. then speed of the owning slot, faster first
##   3. then side index, then slot index
##
## The third rule is never reached in practice. It exists so that ordering can
## never depend on iteration over an unordered collection, which is what makes
## determinism provable rather than merely observed.

## One active effect, with where it is attached. Field effects have no owner.
class Active:
	var instance: VltEffectInstance
	var definition: VltEffectDefinition
	var owner: VltSlotRef

	func _init(held: VltEffectInstance, from: VltEffectDefinition, at: VltSlotRef) -> void:
		instance = held
		definition = from
		owner = at


## Every active effect, in a canonical order: field, then each side, then each
## position with its slot-scoped effects before its creature-scoped ones.
static func active_effects(
	state: VltBattleState, registry: VltEffectRegistry
) -> Array[Active]:
	var found: Array[Active] = []

	for instance: VltEffectInstance in state.effects:
		_append(found, instance, registry, null)

	for side: int in range(VltBattleState.SIDE_COUNT):
		for instance: VltEffectInstance in state.sides[side].effects:
			_append(found, instance, registry, VltSlotRef.at(side, 0))

	for reference: VltSlotRef in state.all_refs():
		for instance: VltEffectInstance in state.slot_at(reference).effects:
			_append(found, instance, registry, reference)

		var creature: VltBattleCreature = state.creature_at(reference)
		if creature != null:
			for instance: VltEffectInstance in creature.effects:
				_append(found, instance, registry, reference)

	return found


static func _append(
	into: Array[Active], instance: VltEffectInstance, registry: VltEffectRegistry, at: VltSlotRef
) -> void:
	if not registry.has(instance.definition_id):
		assert(false, "active effect \"%s\" is not registered" % instance.definition_id)
		return
	into.append(Active.new(instance, registry.definition(instance.definition_id), at))


static func _speed_of(state: VltBattleState, reference: VltSlotRef) -> int:
	if reference == null:
		return 0
	var creature: VltBattleCreature = state.creature_at(reference)
	if creature == null:
		return 0
	var stage: int = state.slot_at(reference).stat_stages[VltStats.Stat.SPE]
	return VltStats.apply_stage(creature.stats[VltStats.Stat.SPE], stage)


## Sorts (active, component) pairs by the rules above. `pairs` holds two-element
## arrays: [Active, VltEffectComponent].
static func _ordered(state: VltBattleState, pairs: Array) -> Array:
	var sorted: Array = pairs.duplicate()
	sorted.sort_custom(
		func(a: Array, b: Array) -> bool:
			var component_a: VltEffectComponent = a[1]
			var component_b: VltEffectComponent = b[1]
			if component_a.priority != component_b.priority:
				return component_a.priority > component_b.priority

			var active_a: Active = a[0]
			var active_b: Active = b[0]
			var speed_a: int = _speed_of(state, active_a.owner)
			var speed_b: int = _speed_of(state, active_b.owner)
			if speed_a != speed_b:
				return speed_a > speed_b

			var side_a: int = active_a.owner.side if active_a.owner != null else -1
			var side_b: int = active_b.owner.side if active_b.owner != null else -1
			if side_a != side_b:
				return side_a < side_b

			var slot_a: int = active_a.owner.slot if active_a.owner != null else -1
			var slot_b: int = active_b.owner.slot if active_b.owner != null else -1
			return slot_a < slot_b
	)
	return sorted


static func _context(
	state: VltBattleState,
	active: Active,
	actor: VltSlotRef,
	target: VltSlotRef,
	move: VltMoveDefinition,
	decider: VltDecider,
	log: VltBattleLog
) -> VltEffectContext:
	var context: VltEffectContext = VltEffectContext.create(state, active.instance, active.owner)
	context.decider = decider
	context.log = log
	return context.with_action(actor, target, move)


## Gathers every stage ratio for one damage computation.
static func collect_modifiers(
	state: VltBattleState,
	registry: VltEffectRegistry,
	actor: VltSlotRef,
	target: VltSlotRef,
	move: VltMoveDefinition
) -> VltDamageModifiers:
	var modifiers: VltDamageModifiers = VltDamageModifiers.new()
	var pairs: Array = []

	for active: Active in active_effects(state, registry):
		for modifier: VltModifier in active.definition.modifiers:
			pairs.append([active, modifier])

	for pair: Array in _ordered(state, pairs):
		var active: Active = pair[0]
		var modifier: VltModifier = pair[1]
		modifier.contribute(_context(state, active, actor, target, move, null, null), modifiers)

	return modifiers


## True as soon as one veto blocks. Remaining vetoes are not consulted: the
## question is answered, and asking on would only invite a side effect.
static func is_vetoed(
	state: VltBattleState,
	registry: VltEffectRegistry,
	anchor: VltTurnAnchor.Anchor,
	actor: VltSlotRef,
	target: VltSlotRef,
	move: VltMoveDefinition
) -> bool:
	var pairs: Array = []

	for active: Active in active_effects(state, registry):
		for veto: VltVeto in active.definition.vetoes:
			if veto.anchor == anchor:
				pairs.append([active, veto])

	for pair: Array in _ordered(state, pairs):
		var active: Active = pair[0]
		var veto: VltVeto = pair[1]
		if veto.blocks(_context(state, active, actor, target, move, null, null)):
			return true

	return false


## Runs every trigger at an anchor, in order.
static func run_triggers(
	state: VltBattleState,
	registry: VltEffectRegistry,
	anchor: VltTurnAnchor.Anchor,
	decider: VltDecider,
	log: VltBattleLog
) -> void:
	var pairs: Array = []

	for active: Active in active_effects(state, registry):
		for trigger: VltTrigger in active.definition.triggers:
			if trigger.anchor == anchor:
				pairs.append([active, trigger])

	for pair: Array in _ordered(state, pairs):
		var active: Active = pair[0]
		var trigger: VltTrigger = pair[1]
		trigger.run(_context(state, active, null, null, null, decider, log))


## Applies an effect, honouring its stacking rule. Returns whether anything
## changed — a UNIQUE effect reapplied is a no-op, not an error.
##
## `at` names the position the effect attaches to; the scope decides which
## container it actually lands in.
static func apply(
	state: VltBattleState,
	registry: VltEffectRegistry,
	id: String,
	at: VltSlotRef,
	source: VltSlotRef
) -> bool:
	var definition: VltEffectDefinition = registry.definition(id)
	if not _can_hold(state, definition.scope, at):
		return false

	var container: Array[VltEffectInstance] = _container_for(state, definition.scope, at)
	var existing: VltEffectInstance = null
	for instance: VltEffectInstance in container:
		if instance.definition_id == id:
			existing = instance
			break

	if existing != null:
		match definition.stacking:
			VltEffectDefinition.Stacking.UNIQUE:
				return false
			VltEffectDefinition.Stacking.REFRESH:
				existing.remaining = definition.default_duration
				return true
			VltEffectDefinition.Stacking.STACKING:
				existing.layers += 1
				return true

	container.append(VltEffectInstance.create(id, source, definition.default_duration))
	return true


static func remove(
	state: VltBattleState, definition: VltEffectDefinition, at: VltSlotRef
) -> bool:
	if not _can_hold(state, definition.scope, at):
		return false

	var container: Array[VltEffectInstance] = _container_for(state, definition.scope, at)
	for index: int in range(container.size()):
		if container[index].definition_id == definition.id:
			container.remove_at(index)
			return true
	return false


## A typed array cannot be null, so "no container" is a separate question from
## "which container". Creature scope is the only one that can be absent: an
## empty slot has no creature to attach to.
static func _can_hold(
	state: VltBattleState, scope: VltEffectDefinition.Scope, at: VltSlotRef
) -> bool:
	if scope == VltEffectDefinition.Scope.FIELD:
		return true
	if at == null or not state.is_valid_ref(at):
		return false
	if scope == VltEffectDefinition.Scope.CREATURE:
		return state.creature_at(at) != null
	return true


static func _container_for(
	state: VltBattleState, scope: VltEffectDefinition.Scope, at: VltSlotRef
) -> Array[VltEffectInstance]:
	if scope == VltEffectDefinition.Scope.FIELD:
		return state.effects
	if scope == VltEffectDefinition.Scope.SIDE:
		return state.sides[at.side].effects
	if scope == VltEffectDefinition.Scope.SLOT:
		return state.slot_at(at).effects
	return state.creature_at(at).effects
