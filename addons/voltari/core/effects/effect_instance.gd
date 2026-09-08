class_name VltEffectInstance
extends RefCounted

## One application of an effect, and the only place an effect keeps state.
##
## Definitions are shared process-wide, so anything that varies between two
## burns — how long each has left, who inflicted it, how many layers — lives
## here. Fully serialisable, because the battle state is.

var definition_id: String = ""

## Who applied it. Null when nothing did, as for a field condition set up by
## the battle itself.
var source: VltSlotRef = null

## Turns left. Meaningless unless `expires` is true.
var remaining: int = 0

## Whether it was given a duration at all. An effect with no duration lasts
## until something removes it, and must not be confused with one whose duration
## has just run out.
var expires: bool = false

## Layers, for STACKING effects. Always at least one.
var layers: int = 1

## Per-effect counters, such as a badly-poisoned turn count. Keyed by the effect
## that owns them; nothing else reads them.
var counters: Dictionary[String, int] = {}


static func create(id: String, applied_by: VltSlotRef, duration: int) -> VltEffectInstance:
	var instance: VltEffectInstance = VltEffectInstance.new()
	instance.definition_id = id
	instance.source = applied_by
	instance.remaining = duration
	instance.expires = duration > 0
	return instance


func counter(name: String) -> int:
	return counters.get(name, 0)


func set_counter(name: String, value: int) -> void:
	counters[name] = value


func clone() -> VltEffectInstance:
	var copy: VltEffectInstance = VltEffectInstance.new()
	copy.definition_id = definition_id
	copy.source = VltSlotRef.at(source.side, source.slot) if source != null else null
	copy.remaining = remaining
	copy.expires = expires
	copy.layers = layers
	copy.counters = counters.duplicate()
	return copy


func to_dict() -> Dictionary:
	return {
		"definition_id": definition_id,
		"source": source.to_array() if source != null else PackedInt32Array(),
		"remaining": remaining,
		"expires": expires,
		"layers": layers,
		"counters": counters,
	}


static func from_dict(data: Dictionary) -> VltEffectInstance:
	var instance: VltEffectInstance = VltEffectInstance.new()
	instance.definition_id = data["definition_id"]
	instance.remaining = data["remaining"]
	instance.expires = data["expires"]
	instance.layers = data["layers"]

	var source_data: PackedInt32Array = PackedInt32Array(data["source"])
	instance.source = VltSlotRef.from_array(source_data) if source_data.size() == 2 else null

	for key: Variant in (data["counters"] as Dictionary).keys():
		instance.counters[key] = (data["counters"] as Dictionary)[key]

	return instance
