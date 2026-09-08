class_name VltMoveDefinition
extends RefCounted

## The static description of a move: what it is, not what it does.
##
## Behaviour beyond dealing damage — secondary effects, status, multi-turn
## charging — belongs to the effect system (spec 06) and attaches by identifier.
## This class holds only the parameters, which is exactly the data/code boundary
## spec 06 draws: parameters in content, behaviour in code.

enum Category {
	PHYSICAL,
	SPECIAL,
	STATUS,
}

const ALWAYS_HITS: int = -1

var id: String = ""
var type: String = "normal"
var category: Category = Category.PHYSICAL
var power: int = 0

## Percentage, or ALWAYS_HITS for moves that bypass the accuracy check entirely
## — which is not the same as 100, since 100 still consults the decider.
var accuracy: int = 100
var priority: int = 0
var max_pp: int = 5


static func create(
	move_id: String,
	move_type: String,
	move_category: Category,
	move_power: int,
	move_accuracy: int = 100,
	move_priority: int = 0,
	pp: int = 5
) -> VltMoveDefinition:
	var move: VltMoveDefinition = VltMoveDefinition.new()
	move.id = move_id
	move.type = move_type
	move.category = move_category
	move.power = move_power
	move.accuracy = move_accuracy
	move.priority = move_priority
	move.max_pp = pp
	return move


func is_damaging() -> bool:
	return category != Category.STATUS and power > 0
