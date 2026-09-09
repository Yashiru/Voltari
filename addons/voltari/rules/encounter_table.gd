class_name VltEncounterTable
extends RefCounted

## What lives in one kind of terrain, and how often (spec 14, section 4).
##
## Plain data. The drawing is a rule and lives in `VltEncounter`.
##
## **The rate belongs here, not to the zone that names this table.** A zone is a
## shape on a map; how dangerous a terrain is belongs with what lives in it.
## Putting the rate on the zone would make the same table feel different on every
## map for no authored reason.

## One line of the table.
class Slot:
	extends RefCounted

	var species_id: String = ""
	var minimum_level: int = 1
	var maximum_level: int = 1

	## Relative, never a percentage. Percentages must sum to 100, which turns
	## adding a creature into an edit of every other line — the change most
	## likely to be made, made as expensive as possible.
	var weight: int = 1

	func _init(species: String, from: int, to: int, share: int) -> void:
		species_id = species
		minimum_level = from
		maximum_level = to
		weight = share


var id: String = ""

## Chance of an encounter per step, in 256ths — see
## `VltEncounterDecider.RATE_DENOMINATOR`.
var rate: int = 0

var slots: Array[Slot] = []


static func create(table_id: String, step_rate: int) -> VltEncounterTable:
	var table: VltEncounterTable = VltEncounterTable.new()
	table.id = table_id
	table.rate = step_rate
	return table


func holds(species_id: String, from: int, to: int, weight: int) -> VltEncounterTable:
	slots.append(Slot.new(species_id, from, to, weight))
	return self


func total_weight() -> int:
	var total: int = 0
	for slot: Slot in slots:
		total += slot.weight
	return total
