class_name VltBattleCreature
extends RefCounted

## A creature taking part in a battle.
##
## Creature scope (spec 03): everything here survives switching out, and most of
## it survives the battle. Volatile state belongs to the slot, not here — which
## is why there are no stat stages on this class.
##
## Stats are derived once, at construction. Nothing in a Gen 4 battle changes
## level, IVs, EVs or nature, and stat stages are a separate multiplier applied
## at use, so a stored spread cannot go stale.

enum Status {
	NONE,
	BURN,
	FREEZE,
	PARALYSIS,
	POISON,
	TOXIC,
	SLEEP,
}

var species_id: String = ""
var types: PackedStringArray = PackedStringArray()
var level: int = 1

var base: PackedInt32Array = PackedInt32Array()
var ivs: PackedInt32Array = PackedInt32Array()
var evs: PackedInt32Array = PackedInt32Array()
var nature_raised: int = VltStats.NO_STAT
var nature_lowered: int = VltStats.NO_STAT

var stats: PackedInt32Array = PackedInt32Array()
var current_hp: int = 0
var status: Status = Status.NONE
var moves: Array[VltMoveSlot] = []


static func create(input: VltStatInput, species: String, creature_types: PackedStringArray) -> VltBattleCreature:
	var creature: VltBattleCreature = VltBattleCreature.new()
	creature.species_id = species
	creature.types = creature_types
	creature.level = input.level
	creature.base = input.base
	creature.ivs = input.ivs
	creature.evs = input.evs
	creature.nature_raised = input.nature_raised
	creature.nature_lowered = input.nature_lowered
	creature.stats = VltStats.derive_spread(input)
	creature.current_hp = creature.stats[VltStats.Stat.HP]
	return creature


func max_hp() -> int:
	return stats[VltStats.Stat.HP]


func is_fainted() -> bool:
	return current_hp <= 0


func clone() -> VltBattleCreature:
	var copy: VltBattleCreature = VltBattleCreature.new()
	copy.species_id = species_id
	copy.types = types.duplicate()
	copy.level = level
	copy.base = base.duplicate()
	copy.ivs = ivs.duplicate()
	copy.evs = evs.duplicate()
	copy.nature_raised = nature_raised
	copy.nature_lowered = nature_lowered
	copy.stats = stats.duplicate()
	copy.current_hp = current_hp
	copy.status = status

	copy.moves = []
	for slot: VltMoveSlot in moves:
		copy.moves.append(slot.clone())

	return copy


func to_dict() -> Dictionary:
	var serialised_moves: Array = []
	for slot: VltMoveSlot in moves:
		serialised_moves.append(slot.to_dict())

	return {
		"species_id": species_id,
		"types": types,
		"level": level,
		"base": base,
		"ivs": ivs,
		"evs": evs,
		"nature_raised": nature_raised,
		"nature_lowered": nature_lowered,
		"stats": stats,
		"current_hp": current_hp,
		"status": status,
		"moves": serialised_moves,
	}


static func from_dict(data: Dictionary) -> VltBattleCreature:
	var creature: VltBattleCreature = VltBattleCreature.new()
	creature.species_id = data["species_id"]
	creature.types = PackedStringArray(data["types"])
	creature.level = data["level"]
	creature.base = PackedInt32Array(data["base"])
	creature.ivs = PackedInt32Array(data["ivs"])
	creature.evs = PackedInt32Array(data["evs"])
	creature.nature_raised = data["nature_raised"]
	creature.nature_lowered = data["nature_lowered"]
	creature.stats = PackedInt32Array(data["stats"])
	creature.current_hp = data["current_hp"]
	creature.status = data["status"]

	creature.moves = []
	for entry: Variant in data["moves"]:
		creature.moves.append(VltMoveSlot.from_dict(entry))

	return creature
