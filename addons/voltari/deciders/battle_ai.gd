class_name VltBattleAi
extends RefCounted

## The opponent's policy (spec 12).
##
## L0bis: it reads a battle and produces a command. It changes nothing and
## resolves nothing, and the turn machine cannot tell it from a player — which is
## what keeps lockstep networking possible later.
##
## Same purity as the core. No engine types, no I/O, no clock, and nothing drawn
## except through VltPolicyDecider.
##
## **It sees only a view** (decision 0034), so it estimates the opponent the way
## a player does: from public species data at a plain spread, not from the real
## creature.

## How well it plays. A named preset rather than loose numbers at the call site,
## so there is somewhere to read what "easy" means.
class Difficulty:
	extends RefCounted

	## Percentage of the time it plays the line it rates highest. Below a hundred
	## it sometimes takes another, which is what stops it being solved.
	var confidence: int = 100

	## What a status move is worth, as a fraction of the target's remaining
	## health. Zero means it never chooses one while a damaging move is available.
	var status_worth: int = 0

	func _init(plays_best: int, status: int) -> void:
		confidence = plays_best
		status_worth = status


## Never chooses well, and never values a status. The floor to measure against.
static func reckless() -> Difficulty:
	return Difficulty.new(0, 0)


static func plain() -> Difficulty:
	return Difficulty.new(70, 15)


static func expert() -> Difficulty:
	return Difficulty.new(100, 30)


## The command for one of its positions.
##
## `species` is content, which an AI may read: what a species is made of is
## public, and a player who has met one knows it too.
static func choose(
	view: VltBattleView,
	slot: int,
	moves: Dictionary[String, VltMoveDefinition],
	species: Dictionary[String, VltSpecies],
	chart: VltTypeChart,
	difficulty: Difficulty,
	decider: VltPolicyDecider
) -> VltCommand:
	var mine: VltBattleView.Combatant = view.mine[slot]
	var target: VltBattleView.Combatant = _first_standing(view.theirs)

	assert(mine.present, "an empty position has nothing to decide")
	assert(target != null, "there is nothing left to act against")

	var usable: PackedInt32Array = _usable(mine, moves)
	assert(not usable.is_empty(), "a creature with no usable move is Struggle, not a choice")

	var scores: PackedInt32Array = PackedInt32Array()
	for index: int in usable:
		scores.append(_score(mine, target, moves[mine.moves[index].move_id], species, chart, difficulty))

	var chosen: int = _pick(usable, scores, difficulty, decider)
	return VltCommand.use_move(mine.reference, chosen, target.reference)


## The best line, or a deliberate departure from it.
static func _pick(
	usable: PackedInt32Array,
	scores: PackedInt32Array,
	difficulty: Difficulty,
	decider: VltPolicyDecider
) -> int:
	if not decider.takes_best_line(difficulty.confidence):
		return usable[decider.among_equals(usable.size())]

	var best: int = scores[0]
	for score: int in scores:
		best = maxi(best, score)

	# Everything tied for best, then one question to break it. Never iteration
	# order: two equal moves must not be settled by which was declared first.
	var tied: PackedInt32Array = PackedInt32Array()
	for index: int in range(usable.size()):
		if scores[index] == best:
			tied.append(usable[index])

	return tied[decider.among_equals(tied.size())]


## What one move is worth against this target.
##
## Damage is estimated with the engine's own pipeline (decision 0035): the same
## code, a fixed average roll and no critical. The estimate cannot drift from the
## real calculation because it is the real calculation.
static func _score(
	mine: VltBattleView.Combatant,
	target: VltBattleView.Combatant,
	move: VltMoveDefinition,
	species: Dictionary[String, VltSpecies],
	chart: VltTypeChart,
	difficulty: Difficulty
) -> int:
	if not move.is_damaging():
		return difficulty.status_worth

	if chart.is_immune(move.type, target.types):
		return 0

	var assumed: PackedInt32Array = _assumed_stats(target, species)

	var input: VltDamageInput = VltDamageInput.new()
	input.level = mine.level
	input.base_power = move.power
	input.attack = VltStats.apply_stage(
		mine.stats[VltDamage.offensive_stat(move.category)],
		mine.stat_stages[VltDamage.offensive_stat(move.category)]
	)
	input.defense = VltStats.apply_stage(
		assumed[VltDamage.defensive_stat(move.category)],
		target.stat_stages[VltDamage.defensive_stat(move.category)]
	)
	input.is_critical = false
	input.has_stab = mine.types.has(move.type)
	input.damage_roll = AVERAGE_ROLL
	input.type_effectiveness_exponent = chart.exponent(move.type, target.types)

	# Capped at what is actually there: overkill is not worth more than a kill,
	# and rating it higher would make the AI prefer a bigger hit to a lethal one.
	return mini(VltDamage.compute(input), target.health)


## The average of the sixteen rolls, so an estimate is neither lucky nor unlucky.
const AVERAGE_ROLL: int = 92

## A plain spread: no effort, average individual values, neutral nature. It is
## what a player assumes about a creature they have only looked at.
const ASSUMED_IV: int = 15


## The opponent's stats as they can be guessed — from the species, never from the
## creature, which the view does not carry (decision 0034).
static func _assumed_stats(
	target: VltBattleView.Combatant, species: Dictionary[String, VltSpecies]
) -> PackedInt32Array:
	assert(species.has(target.species_id), "no species \"%s\" to reason about" % target.species_id)

	var input: VltStatInput = VltStatInput.new()
	input.level = target.level
	input.base = species[target.species_id].base_stats
	for stat: int in range(VltStats.STAT_COUNT):
		input.ivs[stat] = ASSUMED_IV

	return VltStats.derive_spread(input)


static func _usable(
	mine: VltBattleView.Combatant, moves: Dictionary[String, VltMoveDefinition]
) -> PackedInt32Array:
	var usable: PackedInt32Array = PackedInt32Array()
	for index: int in range(mine.moves.size()):
		var slot: VltMoveSlot = mine.moves[index]
		if slot.pp > 0 and moves.has(slot.move_id):
			usable.append(index)
	return usable


static func _first_standing(
	combatants: Array[VltBattleView.Combatant]
) -> VltBattleView.Combatant:
	for combatant: VltBattleView.Combatant in combatants:
		if combatant.present and not combatant.fainted:
			return combatant
	return null
