class_name VltScriptedDecider
extends VltDecider

## The differential harness of spec 02, and any test that wants a battle with no
## randomness in it.
##
## Draws nothing. Every question is answered from a declared policy, decision by
## decision — which is the whole point: the same policy drives the oracle side of
## the differential, so both engines share answers rather than random numbers
## (decision 0009).
##
## Answering every chance the same way is exactly the trap this design exists to
## avoid: a blanket "no" also answers the accuracy roll, and every move misses.

enum Answer {
	NEVER,
	ALWAYS,
}

## Which of the two commands put to the decider wins a speed tie.
##
## Expressed on the pair, not on a side. A side cannot name a winner when the
## two tied commands belong to the same side, which is every ally tie in a
## doubles battle — and the answer then fell out of how the policy happened to
## be written rather than from anything declared.
enum TieWinner {
	EARLIER,
	LATER,
}

## Index into the sixteen damage rolls, 0 to 15.
var damage_roll_index: int = VltSeededDecider.DAMAGE_ROLL_COUNT - 1
var accuracy: Answer = Answer.ALWAYS
var critical: Answer = Answer.NEVER
var secondary: Answer = Answer.NEVER

## Who wins a speed tie. Explicit, because leaving it to iteration order is
## exactly what the decision interface exists to prevent.
var speed_tie_winner: TieWinner = TieWinner.EARLIER

## Multi-hit and status length are answered with fixed values; a scenario that
## needs a different one sets it before running.
var multi_hit: int = 1
var duration: int = 1


func damage_roll() -> int:
	return damage_roll_index


func accuracy_check(_chance: int) -> bool:
	return accuracy == Answer.ALWAYS


func critical_hit(_numerator: int, _denominator: int) -> bool:
	return critical == Answer.ALWAYS


func secondary_triggers(_chance: int) -> bool:
	return secondary == Answer.ALWAYS


func speed_tie(first: VltSlotRef, second: VltSlotRef) -> VltSlotRef:
	return first if speed_tie_winner == TieWinner.EARLIER else second


func multi_hit_count(minimum: int, maximum: int) -> int:
	return clampi(multi_hit, minimum, maximum)


func status_duration(minimum: int, maximum: int) -> int:
	return clampi(duration, minimum, maximum)
