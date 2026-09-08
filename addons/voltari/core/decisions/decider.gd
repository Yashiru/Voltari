class_name VltDecider
extends RefCounted

## Every random decision the engine makes, as named questions.
##
## The core never draws a random number. It asks `damage_roll()`, not
## `randi_range(0, 15)`. Two things follow, and both are the point:
##
## 1. A scripted policy can answer decision by decision (spec 02). A single
##    blanket answer is wrong — the accuracy roll and the critical roll are
##    different questions, and answering both at once makes every move miss.
## 2. Every source of randomness in the engine is enumerable by reading this
##    file. Adding one is a method here, so it is a reviewable event rather than
##    a line buried in a formula.
##
## Probabilities arrive as explicit chances. The rates themselves are formulas
## (spec 08), derived from the oracle, and do not belong to the decider.
##
## Base class rather than an interface, GDScript having none. Every method
## asserts: an unimplemented decision must fail loudly, never return a plausible
## default that silently biases a battle.

const NOT_IMPLEMENTED: String = "VltDecider is abstract; use a seeded or scripted implementation"


## Index into the sixteen Gen 4 damage rolls, 0 to 15.
func damage_roll() -> int:
	assert(false, NOT_IMPLEMENTED)
	return 0


## `chance` is a percentage, 0 to 100.
func accuracy_check(chance: int) -> bool:
	assert(false, NOT_IMPLEMENTED)
	return false


## Gen 4 critical rates are fractions such as 1/16, so the chance arrives as one.
func critical_hit(numerator: int, denominator: int) -> bool:
	assert(false, NOT_IMPLEMENTED)
	return false


## `chance` is a percentage, 0 to 100.
func secondary_triggers(chance: int) -> bool:
	assert(false, NOT_IMPLEMENTED)
	return false


## Which of two equally fast slots acts first.
func speed_tie(first: VltSlotRef, second: VltSlotRef) -> VltSlotRef:
	assert(false, NOT_IMPLEMENTED)
	return first


## How many times a multi-hit move connects, within the inclusive range.
func multi_hit_count(minimum: int, maximum: int) -> int:
	assert(false, NOT_IMPLEMENTED)
	return minimum


## How many turns a status lasts, within the inclusive range.
func status_duration(minimum: int, maximum: int) -> int:
	assert(false, NOT_IMPLEMENTED)
	return minimum
