class_name VltScriptedGenerationDecider
extends VltGenerationDecider

## Draws nothing: every answer is declared up front.
##
## The counterpart of VltScriptedDecider, for the same reason — a creature made
## from declared answers is the same creature every time, which is what makes a
## birth testable at all.
##
## `VltSeededGenerationDecider` is the other half, and it arrived with spec 14:
## encounters are the first thing that generates a creature nobody declared.

## One value per stat, indexed by VltStats.Stat.
var individual_values: PackedInt32Array = PackedInt32Array()

## Which entry of the nature table every creature receives.
var nature_index: int = 0


func _init(value: int = VltGenerationDecider.MAX_INDIVIDUAL_VALUE) -> void:
	individual_values.resize(VltStats.STAT_COUNT)
	individual_values.fill(value)


func individual_value(stat: int) -> int:
	return individual_values[stat]


func nature_choice(count: int) -> int:
	return clampi(nature_index, 0, count - 1)
