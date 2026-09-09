class_name VltScriptedPolicyDecider
extends VltPolicyDecider

## Draws nothing: every answer is declared.
##
## The counterpart of the scripted deciders the other two vocabularies have, and
## for the same reason — an AI given fixed answers plays the same battle every
## time, which is what makes a policy testable at all.

var best_line: bool = true
var equal_choice: int = 0


func _init(takes_best: bool = true, choice: int = 0) -> void:
	best_line = takes_best
	equal_choice = choice


func takes_best_line(_confidence: int) -> bool:
	return best_line


func among_equals(count: int) -> int:
	return clampi(equal_choice, 0, count - 1)
