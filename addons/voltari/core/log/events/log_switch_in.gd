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

## What it arrives on. A party member is not always at full health, so a HUD
## that assumed so would draw a full bar and then jump. Transformed like damage:
## the owner reads exact figures, everyone else reads hundredths.
var current_hp: int = 0
var max_hp: int = 1


static func create(
	slot: VltSlotRef,
	index: int,
	species: String,
	at_level: int = 1,
	hp: int = 0,
	hp_max: int = 1
) -> VltLogSwitchIn:
	var event: VltLogSwitchIn = VltLogSwitchIn.new()
	event.visibility = Visibility.TRANSFORMED
	event.owner_side = slot.side
	event.target = slot
	event.party_index = index
	event.species_id = species
	event.level = at_level
	event.current_hp = hp
	event.max_hp = hp_max
	return event


## Rescaled to hundredths, the way an opponent's bar reads. The species and the
## level stay: both are announced openly the moment a creature appears.
func reduced() -> VltLogEvent:
	var event: VltLogSwitchIn = VltLogSwitchIn.new()
	event.visibility = visibility
	event.owner_side = owner_side
	event.target = target
	event.party_index = party_index
	event.species_id = species_id
	event.level = level
	event.max_hp = REDUCED_SCALE
	event.current_hp = scaled_health(current_hp, max_hp)
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
		"current_hp": current_hp,
		"max_hp": max_hp,
		"species_id": species_id,
	}


static func from_dict(data: Dictionary) -> VltLogSwitchIn:
	var event: VltLogSwitchIn = VltLogSwitchIn.new()
	event._read_common(data)
	event.target = VltSlotRef.from_array(PackedInt32Array(data["target"]))
	event.party_index = data["party_index"]
	event.species_id = data["species_id"]
	event.level = data["level"]
	event.current_hp = data["current_hp"]
	event.max_hp = data["max_hp"]
	return event
