class_name VltEffectRegistry
extends RefCounted

## Effect id to definition, with the per-anchor index dispatch reads.
##
## Indexing at registration rather than at every anchor is what keeps inactive
## effects free: the turn machine asks "which definitions have triggers at
## RESIDUAL" and gets an answer without walking the roster.

var _definitions: Dictionary[String, VltEffectDefinition] = {}


func register(definition: VltEffectDefinition) -> void:
	assert(not _definitions.has(definition.id), "duplicate effect id \"%s\"" % definition.id)
	_definitions[definition.id] = definition


func has(id: String) -> bool:
	return _definitions.has(id)


func definition(id: String) -> VltEffectDefinition:
	assert(_definitions.has(id), "unknown effect id \"%s\"" % id)
	return _definitions[id]


func ids() -> Array[String]:
	var known: Array[String] = []
	for id: String in _definitions.keys():
		known.append(id)
	known.sort()
	return known


func size() -> int:
	return _definitions.size()
