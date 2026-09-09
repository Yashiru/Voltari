class_name VltPolicyDecider
extends RefCounted

## What an AI leaves to chance, asked as named questions.
##
## The third interface of the same pattern, after the battle decider
## (decision 0010) and the generation decider (decision 0029). The rule that
## governs all three is unchanged: **no question appears in two vocabularies**,
## and a meta-test asserts it over every pair.
##
## Three jobs, three vocabularies. A turn asks how the dice fell; a birth asks
## what a creature is; a policy asks whether to take the line it found.
##
## An AI that never varies is solved after three battles. This is where the
## variation is declared, so a replay still reproduces and the fuzzer can drive
## the opponent as well as the dice.
##
## Abstract. Every method asserts, so an implementation that forgets one fails at
## the call rather than returning a plausible answer.

## Whether to play the line the AI rates highest. `confidence` is the difficulty
## preset's percentage, 0 to 100.
func takes_best_line(_confidence: int) -> bool:
	assert(false, "VltPolicyDecider is abstract")
	return false


## Which of `count` equally rated options to take, 0 to count exclusive.
##
## Separate from the question above because they are different: one is whether to
## play well, the other is what to do when playing well leaves a choice.
func among_equals(_count: int) -> int:
	assert(false, "VltPolicyDecider is abstract")
	return 0
