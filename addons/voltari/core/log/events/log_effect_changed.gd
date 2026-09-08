class_name VltLogEffectChanged
extends VltLogEvent

## An effect was applied, refreshed, stacked, counted down or removed.
##
## One event kind for all six, because they are one thing: the state of an
## effect at a position is now this. Splitting them into an "applied" and a
## "removed" vocabulary would need the countdown to re-emit "applied" every
## turn, which is two names for one mechanism.
##
## Carries the resulting instance rather than what changed, like every other
## event: replay assigns. Nothing about the log says whether a screen was set up
## or ticked, and nothing needs to — that is a presentation question answered
## from the values.
##
## It exists because a screen counting down mutated `remaining` with no event at
## all, so replaying a battle produced a screen that had forgotten a turn had
## passed. Invariant 8 could not see it: the only replay test applied a burn,
## whose trigger emits damage.

const KIND: String = "effect_changed"

var definition_id: String = ""
var scope: VltEffectDefinition.Scope = VltEffectDefinition.Scope.SLOT

## Where the effect sits. Null for field scope, which belongs to no position.
var owner: VltSlotRef = null

## Whether the effect is gone. The remaining fields are then meaningless.
var removed: bool = false

var remaining: int = 0
var expires: bool = false
var layers: int = 1
var source: VltSlotRef = null
var counters: Dictionary[String, int] = {}


static func create(
	instance: VltEffectInstance, effect_scope: VltEffectDefinition.Scope, at: VltSlotRef
) -> VltLogEffectChanged:
	var event: VltLogEffectChanged = _at(effect_scope, at)
	event.definition_id = instance.definition_id
	event.remaining = instance.remaining
	event.expires = instance.expires
	event.layers = instance.layers
	event.source = _copy(instance.source)
	event.counters = instance.counters.duplicate()
	return event


static func removal(
	id: String, effect_scope: VltEffectDefinition.Scope, at: VltSlotRef
) -> VltLogEffectChanged:
	var event: VltLogEffectChanged = _at(effect_scope, at)
	event.definition_id = id
	event.removed = true
	return event


static func _at(
	effect_scope: VltEffectDefinition.Scope, at: VltSlotRef
) -> VltLogEffectChanged:
	var event: VltLogEffectChanged = VltLogEffectChanged.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = at.side if at != null else NO_SIDE
	event.scope = effect_scope
	event.owner = _copy(at)
	return event


static func _copy(reference: VltSlotRef) -> VltSlotRef:
	return VltSlotRef.at(reference.side, reference.slot) if reference != null else null


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	# A creature-scoped effect whose slot emptied has nowhere to land. Dropping
	# the event is correct: the container went with the occupant.
	if not VltEffectDispatch.can_hold(state, scope, owner):
		return

	var container: Array[VltEffectInstance] = VltEffectDispatch.container_for(state, scope, owner)
	for index: int in range(container.size()):
		if container[index].definition_id != definition_id:
			continue
		if removed:
			container.remove_at(index)
		else:
			_assign(container[index])
		return

	if removed:
		return

	var instance: VltEffectInstance = VltEffectInstance.create(definition_id, source, remaining)
	_assign(instance)
	container.append(instance)


func _assign(instance: VltEffectInstance) -> void:
	instance.source = _copy(source)
	instance.remaining = remaining
	instance.expires = expires
	instance.layers = layers
	instance.counters = counters.duplicate()


func _payload() -> Dictionary:
	return {
		"definition_id": definition_id,
		"scope": scope,
		"owner": owner.to_array() if owner != null else PackedInt32Array(),
		"removed": removed,
		"remaining": remaining,
		"expires": expires,
		"layers": layers,
		"source": source.to_array() if source != null else PackedInt32Array(),
		"counters": counters,
	}


static func from_dict(data: Dictionary) -> VltLogEffectChanged:
	var event: VltLogEffectChanged = VltLogEffectChanged.new()
	event._read_common(data)
	event.definition_id = data["definition_id"]
	event.scope = data["scope"]
	event.removed = data["removed"]
	event.remaining = data["remaining"]
	event.expires = data["expires"]
	event.layers = data["layers"]

	var owner_data: PackedInt32Array = PackedInt32Array(data["owner"])
	event.owner = VltSlotRef.from_array(owner_data) if owner_data.size() == 2 else null

	var source_data: PackedInt32Array = PackedInt32Array(data["source"])
	event.source = VltSlotRef.from_array(source_data) if source_data.size() == 2 else null

	for key: Variant in (data["counters"] as Dictionary).keys():
		event.counters[key] = (data["counters"] as Dictionary)[key]

	return event
