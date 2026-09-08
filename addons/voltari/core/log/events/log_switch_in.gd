class_name VltLogSwitchIn
extends VltLogEvent

## A party member took a slot. Carries the party index, which is what replay
## needs; the species identifier is what the UI needs.

const KIND: String = "switch_in"

var target: VltSlotRef = null
var party_index: int = 0
var species_id: String = ""


static func create(slot: VltSlotRef, index: int, species: String) -> VltLogSwitchIn:
	var event: VltLogSwitchIn = VltLogSwitchIn.new()
	event.visibility = Visibility.PUBLIC
	event.owner_side = slot.side
	event.target = slot
	event.party_index = index
	event.species_id = species
	return event


func kind() -> String:
	return KIND


func apply(state: VltBattleState) -> void:
	state.slot_at(target).occupy(party_index)


func _payload() -> Dictionary:
	return {
		"target": target.to_array(),
		"party_index": party_index,
		"species_id": species_id,
	}


static func from_dict(data: Dictionary) -> VltLogSwitchIn:
	var event: VltLogSwitchIn = VltLogSwitchIn.new()
	event._read_common(data)
	event.target = VltSlotRef.from_array(PackedInt32Array(data["target"]))
	event.party_index = data["party_index"]
	event.species_id = data["species_id"]
	return event
