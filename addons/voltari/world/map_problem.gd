class_name VltMapProblem
extends RefCounted

## One thing wrong with a map, and enough to go and look at it.
##
## The validator has always produced sentences and the sentences are still what
## a person reads: `message` is unchanged, word for word. Rebuilding it from
## parts would be a second way to say the same thing, and the two would drift the
## first time one of them was reworded.
##
## What is new is beside it rather than instead of it — where the problem is — so
## that a report can be walked to instead of only read. A door painted to nowhere
## was already reported; finding it still meant opening maps and reading cells.
##
## **Not every problem has a place.** "no map has a rest point, so a defeat has
## nowhere to send anybody" is about the whole world, and a map with no id cannot
## name a file. Those carry neither, and a reader that assumed otherwise would
## invent a destination for them.

## The scene to open, or empty when the problem belongs to no single file. Taken
## from the map rather than built from its id, because one of the things checked
## here is precisely that those two disagree.
var scene_path: String = ""

## The cell it is on. Only meaningful when `located` is true.
var cell: Vector2i = Vector2i.ZERO

## Whether `cell` means anything.
##
## A flag rather than an impossible cell. Map coordinates are unbounded in both
## directions, so no value could be reserved honestly — and the sentinel that
## looked safe would be the one somebody eventually painted on.
var located: bool = false

## The sentence, exactly as the validator has always written it.
var message: String = ""


## A problem somewhere in a file, or nowhere at all.
static func of(message: String, scene_path: String = "") -> VltMapProblem:
	var made: VltMapProblem = VltMapProblem.new()
	made.message = message
	made.scene_path = scene_path
	return made


## A problem on one cell of one map.
static func at(message: String, scene_path: String, cell: Vector2i) -> VltMapProblem:
	var made: VltMapProblem = of(message, scene_path)
	made.cell = cell
	made.located = true
	return made


## Whether there is anywhere to send a reader.
func navigable() -> bool:
	return not scene_path.is_empty()
