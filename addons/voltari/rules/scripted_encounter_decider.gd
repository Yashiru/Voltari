class_name VltScriptedEncounterDecider
extends VltEncounterDecider

## Draws nothing: every answer is declared up front.
##
## The counterpart of the other scripted deciders, for the same reason — an
## encounter made from declared answers is the same encounter every time, which
## is what makes the weighting rule testable at all.

## Whether the next step produces an encounter.
var occurs: bool = true

## The point handed back for the slot draw, clamped into the table's weight
## space. Tests that want a particular slot set this to a cumulative offset,
## which is deliberate: it exercises the weighting rather than bypassing it.
var slot_draw: int = 0

## Where in the level range the creature lands, as an offset from the minimum.
var level_offset: int = 0


func _init(happens: bool = true, draw: int = 0) -> void:
	occurs = happens
	slot_draw = draw


func encounter_occurs(_rate: int) -> bool:
	return occurs


func encounter_slot(total_weight: int) -> int:
	return clampi(slot_draw, 0, total_weight - 1)


func encounter_level(minimum: int, maximum: int) -> int:
	return clampi(minimum + level_offset, minimum, maximum)
