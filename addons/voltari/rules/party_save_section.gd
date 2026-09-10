class_name VltPartySaveSection
extends VltSaveSection

## The player's creatures, as a save section (spec 13, section 2).
##
## The third system to declare one, and the first whose contents are the point
## of the game. It lives with the party rather than in `save/`, which is decision
## 0040's general rule holding for a system that knows nothing about the other
## two.
##
## **A creature that cannot be read is dropped, and the rest are kept.** That is
## the opposite of the choice made for a whole section (decision 0036), and
## deliberately: a section is carried through untouched because a later build may
## understand it, but a party with a hole in the middle would renumber every
## creature after it — and party indices are what a save's other halves point at.

const KEY: String = "party"
const VERSION: int = 1
const MEMBERS_FIELD: String = "members"

## The party this reads and writes. Held rather than copied, so that a creature
## wounded in a battle is the creature that gets saved.
var members: Array[VltBattleCreature] = []


func _init(held: Array[VltBattleCreature] = []) -> void:
	members = held


func key() -> String:
	return KEY


func version() -> int:
	return VERSION


func write() -> Dictionary:
	var stored: Array = []
	for creature: VltBattleCreature in members:
		stored.append(creature.to_dict())
	return {MEMBERS_FIELD: stored}


## Reads in place: the array the caller handed over is the one that ends up
## holding the party, so nothing has to be given back and nothing can be given
## back to the wrong place.
func read(stored: Dictionary, _stored_version: int) -> void:
	members.clear()

	var entries: Variant = stored.get(MEMBERS_FIELD, [])
	if not entries is Array:
		return

	@warning_ignore("unsafe_cast")
	for entry: Variant in entries as Array:
		if not entry is Dictionary:
			continue
		@warning_ignore("unsafe_cast")
		var creature: VltBattleCreature = VltBattleCreature.from_dict(entry as Dictionary)
		if creature != null:
			members.append(creature)
