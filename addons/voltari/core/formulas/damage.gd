class_name VltDamage
extends RefCounted

## The Gen 4 damage pipeline.
##
## Stage order is VltDamageStage, extracted from the oracle. Rounding happens
## where the oracle rounds; moving it changes the result. Integer arithmetic
## throughout — a float anywhere in this file is a fidelity defect.
##
## Verified against tests/fixtures/oracle/procedure/damage/stages.json.

## Fixed stage ratios, as the oracle applies them.
const BURN: Array[int] = [1, 2]
const SCREEN: Array[int] = [1, 2]
const SPREAD: Array[int] = [3, 4]
const CRITICAL: Array[int] = [2, 1]
const STAB: Array[int] = [3, 2]

## The oracle's modifier arithmetic: a 4096-denominator fixed-point step with
## round-half-down, applied uniformly across generations. Real Gen 4 hardware
## used plain integer multiply and divide, so this is an inherited
## Showdown-versus-cartridge divergence — accepted by decision 0002, which makes
## the oracle the sole authority.
static func modify(value: int, numerator: int, denominator: int = 1) -> int:
	var modifier: int = numerator * 4096 / denominator
	return (value * modifier + 2048 - 1) / 4096


## Base damage, before any stage applies. Each division truncates, and the
## truncation is part of the specification.
static func base_damage(level: int, base_power: int, attack: int, defense: int) -> int:
	var scaled_level: int = 2 * level / 5 + 2
	return scaled_level * base_power * attack / defense / 50


## Runs the full pipeline. Returns the damage dealt, never below 1.
static func compute(input: VltDamageInput) -> int:
	var damage: int = base_damage(input.level, input.base_power, input.attack, input.defense)

	if input.is_burned:
		damage = modify(damage, BURN[0], BURN[1])

	if input.has_screen:
		damage = modify(damage, SCREEN[0], SCREEN[1])

	if input.is_spread:
		damage = modify(damage, SPREAD[0], SPREAD[1])

	damage = modify(damage, input.weather_numerator, input.weather_denominator)

	# Sits here, not in the base damage. See tools/oracle/gen4-damage-stages.md.
	damage += 2

	if input.is_critical:
		damage = modify(damage, CRITICAL[0], CRITICAL[1])

	# The roll is answered by the decision interface, never drawn here.
	damage = damage * input.damage_roll / 100

	if input.has_stab:
		damage = modify(damage, STAB[0], STAB[1])

	damage = _apply_type_effectiveness(damage, input.type_effectiveness_exponent)

	return maxi(1, damage)


## Repeated integer doubling or halving, never a single multiplier: the halving
## truncates at every step, which a single division would not reproduce.
static func _apply_type_effectiveness(damage: int, exponent: int) -> int:
	var clamped: int = clampi(exponent, -6, 6)
	var result: int = damage

	for _i: int in range(clamped):
		result *= 2
	for _i: int in range(-clamped):
		result = result / 2

	return result
