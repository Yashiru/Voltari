class_name VltStepIntent
extends RefCounted

## Turns a stick into a step (spec 18, section 2; decision 0051).
##
## A stick is continuous and the grid is not, so something has to choose. This
## is that something, and it stops short of the world: it speaks the world's own
## vocabulary — a `VltFacing.Direction` and whether to walk — and knows nothing
## about fingers, keys or devices.
##
## It lives here rather than in `platform/` because it is not about devices at
## all. A device layer produces a vector; this is the grid's intake, and it sits
## beside what it feeds.
##
## Pure, and stateless except for what it must remember: which way the walker is
## already going, and for how long. Both are held by the caller and passed back,
## so two walkers cannot interfere and a test needs no setup.

## Below this, a resting thumb is not a direction.
const DEAD_ZONE: float = 0.35

## How much a new axis must beat the one already held before it takes over.
##
## Near 45° the dominant axis flips on a tremor, and without a margin a player
## walking north-east zigzags one cell at a time. Trying it once feels fine; it
## is the hundredth step that reveals it (decision 0051).
const SWITCH_MARGIN: float = 0.25

## A push shorter than this turns without walking — the thing grid games do that
## nobody notices until it is missing, because it is how you face somebody
## standing beside you.
const FLICK_SECONDS: float = 0.12

## Tuned by feel, all three. They are numbers, not structure.


## What the stick is asking for.
class Step:
	extends RefCounted

	## True when the stick is out of the dead zone at all.
	var wanted: bool = false

	## Which way, and only meaningful when `wanted`.
	var direction: VltFacing.Direction = VltFacing.Direction.SOUTH

	## False while the push is still short enough to be a flick.
	var walk: bool = false

	func _init(is_wanted: bool, which: VltFacing.Direction, should_walk: bool) -> void:
		wanted = is_wanted
		direction = which
		walk = should_walk


## What the caller has to carry between frames. Held outside so that two walkers
## cannot interfere, and so a test can hand over any moment it likes.
class Held:
	extends RefCounted

	var direction: VltFacing.Direction = VltFacing.Direction.SOUTH
	var facing_for: float = 0.0
	var active: bool = false


## `stick` is the raw vector: x to the east, y to the south, the screen's own
## axes. `elapsed` is the time since the last call.
static func of(stick: Vector2, held: Held, elapsed: float) -> Step:
	if stick.length() < DEAD_ZONE:
		held.active = false
		held.facing_for = 0.0
		return Step.new(false, held.direction, false)

	var wanted: VltFacing.Direction = _quantise(stick, held)

	if not held.active or wanted != held.direction:
		# A new direction restarts the clock, which is what makes a flick a
		# flick: it is short *in this direction*, not short since the stick moved.
		held.direction = wanted
		held.facing_for = 0.0
		held.active = true
	else:
		held.facing_for += elapsed

	return Step.new(true, wanted, held.facing_for >= FLICK_SECONDS)


## The dominant axis wins, and the direction already held keeps a margin. There
## are no diagonals because there are no diagonal steps.
static func _quantise(stick: Vector2, held: Held) -> VltFacing.Direction:
	var horizontal: float = absf(stick.x)
	var vertical: float = absf(stick.y)

	var wants_horizontal: bool = horizontal > vertical
	if held.active:
		# Whichever axis is already in use has to be beaten, not merely matched.
		if _is_horizontal(held.direction):
			wants_horizontal = horizontal + SWITCH_MARGIN > vertical
		else:
			wants_horizontal = horizontal > vertical + SWITCH_MARGIN

	if wants_horizontal:
		return VltFacing.Direction.EAST if stick.x > 0.0 else VltFacing.Direction.WEST
	return VltFacing.Direction.SOUTH if stick.y > 0.0 else VltFacing.Direction.NORTH


static func _is_horizontal(direction: VltFacing.Direction) -> bool:
	return direction == VltFacing.Direction.EAST or direction == VltFacing.Direction.WEST


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
