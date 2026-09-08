class_name VltRecordingEffects
extends RefCounted

## Test doubles that record the order in which dispatch ran them.
##
## Ordering is the one thing about the effect system that no real effect can
## demonstrate: burn and reflect never contend, so a comparator that returned
## its arguments in any order at all would pass every test written against them.
## These record instead of doing, so the order itself becomes the assertion.
##
## A component is shared across every battle in the process and must store no
## per-run state (spec 06), so the trace lives here rather than on the component.
## The label each one carries is configuration, like a modifier's stage.

static var trace: PackedStringArray = PackedStringArray()


static func reset() -> void:
	trace = PackedStringArray()


static func _record(label: String) -> void:
	trace.append(label)


class RecordingTrigger:
	extends VltTrigger

	var label: String = ""

	func _init(at: VltTurnAnchor.Anchor, order: int, name: String) -> void:
		super(at, order)
		label = name

	func run(_context: VltEffectContext) -> void:
		VltRecordingEffects._record(label)


class RecordingVeto:
	extends VltVeto

	var label: String = ""
	var answer: bool = false

	func _init(at: VltTurnAnchor.Anchor, order: int, name: String, blocking: bool) -> void:
		super(at, order)
		label = name
		answer = blocking

	func blocks(_context: VltEffectContext) -> bool:
		VltRecordingEffects._record(label)
		return answer


class RecordingModifier:
	extends VltModifier

	var label: String = ""

	func _init(at: VltDamageStage.Stage, order: int, name: String) -> void:
		super(at, order)
		label = name

	func contribute(_context: VltEffectContext, modifiers: VltDamageModifiers) -> void:
		VltRecordingEffects._record(label)
		modifiers.contribute(stage, 1, 1)


## An effect whose only behaviour is to announce when it ran.
static func trigger_effect(
	id: String,
	scope: VltEffectDefinition.Scope,
	anchor: VltTurnAnchor.Anchor,
	priority: int
) -> VltEffectDefinition:
	return VltEffectDefinition.create(id, scope).with_trigger(
		RecordingTrigger.new(anchor, priority, id)
	)


static func veto_effect(
	id: String,
	scope: VltEffectDefinition.Scope,
	anchor: VltTurnAnchor.Anchor,
	priority: int,
	blocking: bool
) -> VltEffectDefinition:
	return VltEffectDefinition.create(id, scope).with_veto(
		RecordingVeto.new(anchor, priority, id, blocking)
	)


static func modifier_effect(
	id: String,
	scope: VltEffectDefinition.Scope,
	stage: VltDamageStage.Stage,
	priority: int
) -> VltEffectDefinition:
	return VltEffectDefinition.create(id, scope).with_modifier(
		RecordingModifier.new(stage, priority, id)
	)
