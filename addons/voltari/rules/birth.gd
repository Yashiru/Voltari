class_name VltBirth
extends RefCounted

## A creature at a level, from a species (spec 10, section 2).
##
## L1: same purity as the core. Nothing is drawn here — every value that is not
## derived or read comes from the generation decider, so the same answers give
## the same creature, field for field.
##
## Nothing is left to be decided later. A half-built creature reaching the core
## would be a defect the core has no vocabulary to describe.

const MOVE_LIMIT: int = 4
const MIN_LEVEL: int = 1
const MAX_LEVEL: int = 100


## `natures` is the nature table as (raised, lowered) stat pairs; the decider
## picks one by index. `moves` supplies the PP a freshly learned move starts on.
## `curve` is the species' experience table, which sets where a creature born at
## this level already stands — without it the first award it ever earned would
## drop it back to level one.
static func at_level(
	species: VltSpecies,
	level: int,
	natures: Array[PackedInt32Array],
	moves: Dictionary[String, VltMoveDefinition],
	curve: PackedInt32Array,
	decider: VltGenerationDecider
) -> VltBattleCreature:
	assert(level >= MIN_LEVEL and level <= MAX_LEVEL, "level %d is out of range" % level)
	assert(not natures.is_empty(), "the nature table is empty")
	assert(level <= curve.size(), "the curve does not reach level %d" % level)

	var input: VltStatInput = VltStatInput.new()
	input.level = level
	input.base = species.base_stats

	for stat: int in range(VltStats.STAT_COUNT):
		var iv: int = decider.individual_value(stat)
		assert(
			iv >= 0 and iv <= VltGenerationDecider.MAX_INDIVIDUAL_VALUE,
			"individual value %d for stat %d is out of range" % [iv, stat]
		)
		input.ivs[stat] = iv

	# EVs are earned, never granted at birth (spec 10, section 5).
	var nature: PackedInt32Array = natures[decider.nature_choice(natures.size())]
	input.nature_raised = nature[0]
	input.nature_lowered = nature[1]

	var creature: VltBattleCreature = VltBattleCreature.create(
		input, species.id, species.types
	)
	creature.experience = curve[level - 1]

	for move_id: String in moves_at_level(species, level):
		assert(moves.has(move_id), "species \"%s\" learns unknown move \"%s\"" % [species.id, move_id])
		creature.moves.append(VltMoveSlot.create(move_id, moves[move_id].max_pp))

	return creature


## The moves a creature born at `level` knows: the last four it would have
## learned, in the order it learned them.
##
## A move relearned later keeps its later position rather than appearing twice —
## a creature holding one move in two slots would be a defect nothing else could
## explain.
static func moves_at_level(species: VltSpecies, level: int) -> PackedStringArray:
	var learned: PackedStringArray = PackedStringArray()

	for entry: VltSpecies.Learned in species.learnset:
		if entry.level > level:
			continue
		var seen: int = learned.find(entry.move_id)
		if seen != -1:
			learned.remove_at(seen)
		learned.append(entry.move_id)

	if learned.size() <= MOVE_LIMIT:
		return learned
	return learned.slice(learned.size() - MOVE_LIMIT)
