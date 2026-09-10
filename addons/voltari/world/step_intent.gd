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

## How hard *both* axes have to be pushed before it counts as a deliberate
## diagonal.
##
## The switch margin below exists to stop an analog stick near 45 degrees from
## flipping axis on a tremor, and it still does: a tremor is a small second axis,
## and this floor is far above one. Two keys held, or a thumb parked on the
## diagonal, clear it easily — and those are unambiguous.
const DIAGONAL_FLOOR: float = 0.55

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

	## Which axis the last step used. Only read while both axes are pushed, and
	## it is what makes the next one take the other axis.
	var stepped_horizontal: bool = false

	## Told by the caller when a step was actually taken.
	##
	## The quantiser says what is wanted every frame; only the caller knows which
	## of those became a step, because only the caller holds the cooldown. A
	## diagonal that alternated per frame instead of per step would spin on the
	## spot.
	func stepped(taken: VltFacing.Direction) -> void:
		stepped_horizontal = (
			taken == VltFacing.Direction.EAST or taken == VltFacing.Direction.WEST
		)

	## Tells the quantiser which way the walker was turned by something other
	## than the stick — a warp arriving, a flick, a script.
	##
	## Without it there are two records of one fact and they drift: the walker
	## faces east because a door said so, the quantiser still believes north, and
	## the next tap east turns instead of walking. One writer per fact, and this
	## is the door for the other writers.
	func face(turned: VltFacing.Direction) -> void:
		direction = turned
		facing_for = 0.0
		active = false


## `stick` is the raw vector: x to the east, y to the south, the screen's own
## axes. `elapsed` is the time since the last call.
static func of(stick: Vector2, held: Held, elapsed: float) -> Step:
	if stick.length() < DEAD_ZONE:
		held.active = false
		held.facing_for = 0.0
		return Step.new(false, held.direction, false)

	var was_facing: VltFacing.Direction = held.direction
	var wanted: VltFacing.Direction = _quantise(stick, held)

	# A diagonal changes axis on purpose, every step. Treating that as a new
	# direction would restart the flick clock at each cell and the walk would
	# stall halfway through every second step.
	var turning_afresh: bool = wanted != was_facing and not is_diagonal(stick)
	held.direction = wanted

	if turning_afresh:
		# A new direction restarts the clock, which is what makes a flick a
		# flick: it is short *in this direction*, not short since the stick moved.
		held.facing_for = 0.0
	elif not held.active:
		# Pushed again in the direction it was already facing. **This walks at
		# once.** A flick is how you turn to face something beside you, so it has
		# nothing to say about a direction you are already facing — and restarting
		# the clock here made every tap a turn to where you already looked, which
		# is a tap that does nothing at all.
		held.facing_for = FLICK_SECONDS if wanted == was_facing else 0.0
	else:
		held.facing_for += elapsed

	held.active = true
	return Step.new(true, wanted, held.facing_for >= FLICK_SECONDS)


## Whether both axes are being pushed hard enough to mean it.
static func is_diagonal(stick: Vector2) -> bool:
	return absf(stick.x) >= DIAGONAL_FLOOR and absf(stick.y) >= DIAGONAL_FLOOR


## The dominant axis wins, and the direction already held keeps a margin.
##
## **There are still no diagonal steps** (spec 14, section 2). What a diagonal
## push produces is an alternation: east, north, east, north, one cell at a time
## and with no pause between them, which is a staircase the eye reads as a
## diagonal. Every one of those is an ordinary step, so walkability, warps,
## events and encounter checks all happen exactly as they always did — twice,
## because two cells really were crossed.
static func _quantise(stick: Vector2, held: Held) -> VltFacing.Direction:
	var horizontal: float = absf(stick.x)
	var vertical: float = absf(stick.y)

	if is_diagonal(stick):
		return _towards(not held.stepped_horizontal, stick)

	var wants_horizontal: bool = horizontal > vertical
	if held.active:
		# Whichever axis is already in use has to be beaten, not merely matched.
		if _is_horizontal(held.direction):
			wants_horizontal = horizontal + SWITCH_MARGIN > vertical
		else:
			wants_horizontal = horizontal > vertical + SWITCH_MARGIN

	return _towards(wants_horizontal, stick)


static func _towards(horizontally: bool, stick: Vector2) -> VltFacing.Direction:
	if horizontally:
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
