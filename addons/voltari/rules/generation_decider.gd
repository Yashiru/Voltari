class_name VltGenerationDecider
extends RefCounted

## What is drawn when a creature is made, asked as named questions.
##
## The same pattern as the battle decider (decision 0010), applied a second time
## rather than by widening the first. `VltDecider` carries the policy shared with
## the oracle, and that class must stay exactly as wide as what both engines
## agree on — see decision 0029.
##
## The two vocabularies are **disjoint by construction**: no question appears in
## both, and a meta-test asserts it. That is what keeps this one pattern applied
## twice rather than two ways of doing one thing.
##
## Abstract. Every method asserts, so an implementation that forgets one fails
## loudly at the call rather than returning a plausible number.

## Individual values run 0 to 31 inclusive. The bound lives here rather than on
## VltStats: deriving a stat takes an IV and does not care where it came from,
## so the range is a rule about making creatures, not about arithmetic.
const MAX_INDIVIDUAL_VALUE: int = 31

## A single stat's individual value, 0 to 31 inclusive.
func individual_value(_stat: int) -> int:
	assert(false, "VltGenerationDecider is abstract")
	return 0


## An index into the nature table, 0 to `count` exclusive. An index rather than
## a nature id: the pair of stats is all a creature stores, so nothing downstream
## needs the name.
func nature_choice(_count: int) -> int:
	assert(false, "VltGenerationDecider is abstract")
	return 0
