class_name BattleClips
extends RefCounted

## What an event makes a creature do (spec 17, section 6).
##
## Spec 16 gives every creature the same clip vocabulary; this is the single
## place that asks for it. One table, so a creature with an unusual animation
## never needs the reader to know about it — and so "what plays when" is a
## question with an answer in one file.
##
## An event may move two creatures at once: an attack plays on the actor and its
## landing plays on the target. Both are returned, because a reader that had to
## infer the second would infer it differently for each kind.

## One creature, one clip.
class Cue:
	extends RefCounted

	var at: VltSlotRef = null
	var slot: String = ""

	func _init(position: VltSlotRef, clip: String) -> void:
		at = position
		slot = clip


## The clips an event asks for, in the order they start.
static func of(event: VltLogEvent, moves: Dictionary[String, VltMoveDefinition]) -> Array[Cue]:
	var cues: Array[Cue] = []

	if event is VltLogMoveUsed:
		var used: VltLogMoveUsed = event as VltLogMoveUsed
		cues.append(Cue.new(used.actor, _attack(used.move_id, moves)))
	elif event is VltLogDamage:
		cues.append(Cue.new((event as VltLogDamage).target, "hurt"))
	elif event is VltLogFaint:
		cues.append(Cue.new((event as VltLogFaint).target, "faint"))
	elif event is VltLogSwitchIn:
		cues.append(Cue.new((event as VltLogSwitchIn).target, "enter"))

	return cues


## Physical or special, from the move rather than from the event: the log says
## which move was used and the move says what kind of thing it is. A status move
## still plays the special animation — it is the one that does not make contact.
static func _attack(move_id: String, moves: Dictionary[String, VltMoveDefinition]) -> String:
	if not moves.has(move_id):
		return "attack_special"
	if moves[move_id].category == VltMoveDefinition.Category.PHYSICAL:
		return "attack_physical"
	return "attack_special"
