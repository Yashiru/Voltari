class_name VltEffectComponent
extends RefCounted

## Base of the three component types, and of nothing else.
##
## Three types is the whole vocabulary (decision 0015). A behaviour that seems
## to want a fourth is telling you the anchor set is wrong, not that the
## vocabulary should grow.
##
## Components hang off definitions, which are shared across every battle in the
## process. A component that stores anything in itself is therefore a defect,
## not a style choice: per-effect state lives on the instance, reached through
## the context.

## Orders components within one anchor. Ties fall through to speed order, then
## to a deterministic tiebreak — never to iteration order (spec 06).
var priority: int = 0


func _init(order: int = 0) -> void:
	priority = order
