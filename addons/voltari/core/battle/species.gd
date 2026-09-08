class_name VltSpecies
extends RefCounted

## What a creature is, as data.
##
## Here rather than in the rules layer so a creature can say what it is during a
## battle — mechanics that read the species exist, and a creature that had
## forgotten where it came from could not serve them.
##
## The core reads `types` and `base_stats`. Everything below them is carried for
## L1, where progression lives (spec 10). One type rather than a core view and a
## rules view of the same entity: two shapes for one thing is two things to keep
## in step, and nothing here is expensive enough to justify the split.
##
## Plain data. Which moves a creature is born with, and when it evolves, are
## rules and live with the rules.

## Eighths female. A species with no gender uses this instead of a ratio.
const GENDERLESS: int = -1

## One entry of a level-up learnset.
class Learned:
	extends RefCounted

	var level: int = 1
	var move_id: String = ""

	func _init(at: int, move: String) -> void:
		level = at
		move_id = move


## One way this species becomes another. `trigger` names code, never a condition
## written in the content (spec 06, section 8).
class Evolution:
	extends RefCounted

	var into: String = ""
	var trigger: String = ""
	var level: int = 0

	func _init(target: String, by: String, at: int) -> void:
		into = target
		trigger = by
		level = at


var id: String = ""
var types: PackedStringArray = PackedStringArray()
var base_stats: PackedInt32Array = PackedInt32Array()

## In the order the content declares, which the build has already checked is
## ascending — re-sorting here would hide an authoring mistake rather than let
## it be reported (spec 09, section 8).
var learnset: Array[Learned] = []
var evolutions: Array[Evolution] = []

var growth_rate: String = ""
var base_experience: int = 0
var ev_yield: PackedInt32Array = PackedInt32Array()
var catch_rate: int = 0
var gender_ratio: int = GENDERLESS


static func create(
	species_id: String, species_types: PackedStringArray, stats: PackedInt32Array
) -> VltSpecies:
	assert(species_types.size() >= 1 and species_types.size() <= 2, "a species has one or two types")
	assert(stats.size() == VltStats.STAT_COUNT, "base stats are indexed by VltStats.Stat")

	var species: VltSpecies = VltSpecies.new()
	species.id = species_id
	species.types = species_types
	species.base_stats = stats
	species.ev_yield = PackedInt32Array()
	species.ev_yield.resize(VltStats.STAT_COUNT)
	return species


func learns(at: int, move_id: String) -> VltSpecies:
	learnset.append(Learned.new(at, move_id))
	return self


func evolves(into: String, trigger: String, at: int) -> VltSpecies:
	evolutions.append(Evolution.new(into, trigger, at))
	return self
