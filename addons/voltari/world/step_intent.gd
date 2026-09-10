class_name VltStepIntent
extends RefCounted

## Turns keys and thumbs into a direction (spec 18, section 2).
##
## **Most of what was here is gone**, and the reason is decision 0058: the world
## stopped being grid-locked, so a stick no longer needs quantising into one of
## four. It is now the direction of travel, and the two jobs left are the two
## that were never about the grid — reading a keyboard as a vector, and knowing
## when a thumb is resting.
##
## What went with it: the dominant axis, the bias near 45 degrees (decision
## 0051), the flick that turned without walking, and the staircase two keys used
## to trace (decision 0056). Free movement answers all four by not asking the
## question. Both decisions are superseded rather than deleted, and say so.
##
## It lives here rather than in `platform/` because it is not about devices at
## all. A device layer produces a vector; this is the world's intake, and it sits
## beside what it feeds.

## Below this, a resting thumb is not a direction.
##
## The one number that survived. Without it a stick at rest walks, and a stick
## is never quite at rest.
const DEAD_ZONE: float = 0.35


## A key held is a stick pinned to an axis. The same function serves both, which
## is what makes a keyboard and a phone unable to drift apart.
static func from_keys(north: bool, south: bool, east: bool, west: bool) -> Vector2:
	var stick: Vector2 = Vector2.ZERO
	if north:
		stick.y -= 1.0
	if south:
		stick.y += 1.0
	if east:
		stick.x += 1.0
	if west:
		stick.x -= 1.0
	return stick


## What the stick is asking for: a direction, or nothing.
##
## Clamped rather than normalised, so a thumb held halfway walks at half pace and
## a key held is always full. Normalising would make a stick a switch.
static func of(stick: Vector2) -> Vector2:
	if stick.length() < DEAD_ZONE:
		return Vector2.ZERO
	return stick if stick.length() <= 1.0 else stick.normalized()
