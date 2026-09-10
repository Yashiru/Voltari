class_name BattleStage
extends RefCounted

## What a reader needs the world to be able to do (spec 17, section 2).
##
## Abstract, and deliberately small: four things, none of which decides
## *whether* something happens. The reader sequences; a stage renders.
##
## **Every method may be a coroutine.** The reader awaits each one, so a stage
## that animates takes as long as it likes and a stage that records takes no time
## at all. That is also how skipping works — see `skipping`.
##
## A recording stand-in of this is what lets the reader be tested without a
## scene, which is the whole reason it is an interface rather than a node.


## Play a clip on whoever is at a position, and return when it has finished.
##
## "Finished" is the clip's own length, not a number the reader chose. A fixed
## wait runs the next thing over the top of a long attack and leaves a gap after
## a short one — and that gap is what makes a hit look late.
func play(_at: VltSlotRef, _slot: String) -> void:
	pass


## Show a line and return when it has been read.
func say(_line: BattleLines.Line) -> void:
	pass


## Redraw from the view. Bars move here.
func refresh(_view: VltBattleView) -> void:
	pass


## Whether the player is holding the button.
##
## The reader never asks. It is here because a stage needs somewhere to put the
## answer, and because putting it on the reader would invite a branch — see
## `VltBattleLogReader`, which has none.
func skipping() -> bool:
	return false
