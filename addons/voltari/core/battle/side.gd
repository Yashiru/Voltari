class_name VltSide
extends RefCounted

## One of the two sides of a battle: its party, and its slots on the field.
##
## Side scope (spec 03): conditions attached to the side rather than to whoever
## occupies its slots — entry hazards, screens. They survive switching, which is
## the whole point of the scope existing.

var party: Array[VltBattleCreature] = []
var slots: Array[VltSlot] = []


static func create(slot_count: int) -> VltSide:
	assert(slot_count > 0, "a side needs at least one slot")
	var side: VltSide = VltSide.new()
	for _i: int in range(slot_count):
		side.slots.append(VltSlot.new())
	return side


func creature_in(slot_index: int) -> VltBattleCreature:
	var slot: VltSlot = slots[slot_index]
	if slot.is_empty():
		return null
	return party[slot.occupant]


func has_available_switch() -> bool:
	for index: int in range(party.size()):
		if party[index].is_fainted():
			continue
		if not _is_on_field(index):
			return true
	return false


func _is_on_field(party_index: int) -> bool:
	for slot: VltSlot in slots:
		if slot.occupant == party_index:
			return true
	return false


func clone() -> VltSide:
	var copy: VltSide = VltSide.new()

	copy.party = []
	for creature: VltBattleCreature in party:
		copy.party.append(creature.clone())

	copy.slots = []
	for slot: VltSlot in slots:
		copy.slots.append(slot.clone())

	return copy


func to_dict() -> Dictionary:
	var serialised_party: Array = []
	for creature: VltBattleCreature in party:
		serialised_party.append(creature.to_dict())

	var serialised_slots: Array = []
	for slot: VltSlot in slots:
		serialised_slots.append(slot.to_dict())

	return {"party": serialised_party, "slots": serialised_slots}


static func from_dict(data: Dictionary) -> VltSide:
	var side: VltSide = VltSide.new()

	for entry: Variant in data["party"]:
		side.party.append(VltBattleCreature.from_dict(entry))

	for entry: Variant in data["slots"]:
		side.slots.append(VltSlot.from_dict(entry))

	return side
