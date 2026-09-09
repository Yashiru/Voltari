class_name VltLogSwitchIn
extends VltLogEvent

## A party member took a slot. Carries the party index, which is what replay
## needs; the species identifier is what the UI needs.

const KIND: String = "switch_in"

var target: VltSlotRef = null
var party_index: int = 0
var species_id: String = ""

## Public: every game of this kind shows the opponent's level, and a creature
## that entered mid-battle has no other way of announcing it. The differential
## projects a switch onto its side and slot only, so this is invisible there.
var level: int = 1


static func create(
	slot: VltSlotRef, index: int, species: String, at_level: int = 1
) -> VltLogSwitchIn:
	var event: VltLogSwitchIn = VltLogSwitchIn.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = slot.side
	event.target = slot
	event.party_index = index
	event.species_id = species
	event.level = at_level
	return event


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	state.slot_at(target).occupy(party_index)


func _payload() -> Dictionary:
	return {
		"target": target.to_array(),
		"party_index": party_index,
		"level": level,
		"species_id": species_id,
	}


static func from_dict(data: Dictionary) -> VltLogSwitchIn:
	var event: VltLogSwitchIn = VltLogSwitchIn.new()
	event._read_common(data)
	event.target = VltSlotRef.from_array(PackedInt32Array(data["target"]))
	event.party_index = data["party_index"]
	event.species_id = data["species_id"]
	event.level = data["level"]
	return event
