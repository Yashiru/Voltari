class_name VltEncounter
extends RefCounted

## Whether something appears, and what (spec 14, section 5).
##
## L1: same purity as the core. Nothing is drawn here — every value comes from
## the encounter decider, so the same answers give the same encounter.
##
## This is the half of the overworld that carries numbers, and therefore the
## half that can be **wrong quietly**: a slot drawn 1.4 times too often is
## indistinguishable from luck in any single draw. That is why it lives here and
## not in the scene tree (decision 0038).
##
## It produces a species and a level and stops. Turning those into a creature is
## `VltBirth`, and assembling a battle is nobody's business here.


## What a step produced.
class Outcome:
	extends RefCounted

	var species_id: String = ""
	var level: int = 1

	func _init(species: String, at: int) -> void:
		species_id = species
		level = at


## Whether this step produces an encounter at all.
static func occurs(table: VltEncounterTable, decider: VltEncounterDecider) -> bool:
	assert(
		table.rate >= 0 and table.rate <= VltEncounterDecider.RATE_DENOMINATOR,
		"encounter rate %d is outside the range a rate can express" % table.rate
	)
	return decider.encounter_occurs(table.rate)


## Which creature, at which level. Only meaningful once `occurs` has said yes;
## calling it regardless would draw from a table nothing asked for.
static func draw(table: VltEncounterTable, decider: VltEncounterDecider) -> Outcome:
	var slot: VltEncounterTable.Slot = slot_at(table, decider.encounter_slot(table.total_weight()))
	var level: int = decider.encounter_level(slot.minimum_level, slot.maximum_level)

	assert(
		level >= slot.minimum_level and level <= slot.maximum_level,
		"level %d is outside the slot's range" % level
	)
	return Outcome.new(slot.species_id, level)


## The slot a point in the weight space falls in.
##
## Cumulative rather than proportional: each slot owns the half-open interval
## `[running, running + weight)`, so a weight of zero owns nothing and can never
## be drawn, and the intervals cover `[0, total)` exactly once.
static func slot_at(table: VltEncounterTable, draw_point: int) -> VltEncounterTable.Slot:
	var total: int = table.total_weight()
	assert(not table.slots.is_empty(), "table \"%s\" has no slots" % table.id)
	assert(total > 0, "table \"%s\" has no weight to draw from" % table.id)
	assert(
		draw_point >= 0 and draw_point < total,
		"draw %d is outside table \"%s\"" % [draw_point, table.id]
	)

	var running: int = 0
	for slot: VltEncounterTable.Slot in table.slots:
		running += slot.weight
		if draw_point < running:
			return slot

	# Unreachable: the weights sum to `total` and the draw is below it. Kept
	# because a silent null here would surface as a crash somewhere else.
	assert(false, "the weights of table \"%s\" do not cover its own total" % table.id)
	return table.slots[table.slots.size() - 1]
