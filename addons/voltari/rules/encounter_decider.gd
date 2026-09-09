class_name VltEncounterDecider
extends RefCounted

## What is drawn when the world asks whether something appears (spec 14).
##
## The fourth vocabulary, and the same pattern as the other three (decisions
## 0010 and 0029). It sits closest to the generation decider, since a wild
## encounter runs straight into a birth — which is exactly why it is separate.
## The world asks **where and when**; birth asks **with what**. Two vocabularies
## that run back to back are the ones most easily merged and then answered in a
## context neither was written for.
##
## The vocabularies are disjoint by construction: no question appears in two,
## and a meta-test asserts it across all six pairs.
##
## Abstract. Every method asserts, so an implementation that forgets one fails
## loudly at the call rather than returning a plausible number.

## An encounter rate is in 256ths, the way an accuracy is in 100ths. The
## denominator lives here because it is the shape of the *question* — what a
## caller must scale its rate to before asking — not a property of any answer.
const RATE_DENOMINATOR: int = 256


## Whether an encounter happens on this step, against a rate in 256ths.
func encounter_occurs(_rate: int) -> bool:
	assert(false, "VltEncounterDecider is abstract")
	return false


## A point in [0, total_weight), which the table's cumulative weights turn into
## a slot.
##
## A point rather than a slot index: the weighting is a rule, and a rule that
## lived inside the decider would be written once per implementation and tested
## in none of them.
func encounter_slot(_total_weight: int) -> int:
	assert(false, "VltEncounterDecider is abstract")
	return 0


## A level in [minimum, maximum], both ends inclusive. The decider returns the
## level itself, the way it returns a multi-hit count rather than an offset.
func encounter_level(_minimum: int, _maximum: int) -> int:
	assert(false, "VltEncounterDecider is abstract")
	return 0
