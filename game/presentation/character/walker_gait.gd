class_name WalkerGait
extends RefCounted

## How fast a character's legs should move, which way it should be turned, and
## what a turn on the spot costs.
##
## Pure arithmetic, no nodes. It exists because the numbers underneath it are
## **measured** rather than chosen, and a measurement nobody can re-run is an
## assertion. `tools/characters/measure_clips.gd` prints them; this is where they
## are used.
##
## ## Where the speeds come from
##
## An in-place clip is a clip with the root's travel taken out, so the foot that
## is on the ground moves backwards, relative to the body, at exactly the ground
## speed. That is read off the clip directly, on this character's own rig, after
## the retarget — both feet agree to within two percent, which is what makes it a
## measurement and not an estimate.
##
## The numbers this replaced came from a cadence times a step length taken as a
## fraction of the character's height. The cadence was honest; the fraction was
## anthropometry, and this character is 1.70 m tall with 0.64 m legs and a head a
## third of its height. It ran 8% fast and walked 11% fast, which is a foot that
## slides forward and nothing in the code to explain it.
##
## ## Why the turns are not 90 and 180
##
## The four turn clips were ordered as quarter and half turns and they are not:
## measured on the rig they deliver 89°, 102°, 176° and 175°. A turn played
## without knowing that ends pointing somewhere nobody asked for — twelve degrees
## out, every time, on one of the four. So a turn is **warped**: the clip supplies
## the motion, the body supplies the exact angle, and the ratio between them is
## kept inside a band where nobody can see the difference.

## The speed each gait was authored for, in metres per second.
##
## Measured, and re-measurable. `walk` reads 1.32 and 1.34 off the two feet,
## `run` 3.36 and 3.29.
const LOOKS_RIGHT_AT: Dictionary[String, float] = {
	HumanoidClips.WALK: 1.33,
	HumanoidClips.RUN: 3.33,
}

## How far a gait's playback may be pushed from what it was authored for.
##
## Outside this the cadence stops being human: a run at twice the rate is 340
## steps a minute, which no amount of correct footfall makes look like running.
## Inside it, the error is a foot that slides — which every game has and nobody
## sees.
const SLOWEST_RATE: float = 0.80
const FASTEST_RATE: float = 1.25

## How fast a character turns when it is not playing a turn clip, in radians a
## second. A quarter turn takes about a tenth of a second, which is under one
## step: the turn is finished before the walk that follows it starts, and it is
## never what you are waiting for.
const TURN_SPEED: float = 14.0

## Below this a character is standing still, whatever the arithmetic says.
const STILL: float = 0.01

# --- turning on the spot ------------------------------------------------------

## How far into the throw the ball leaves the hand, as a fraction of the clip.
##
## Measured as the moment the throwing hand is travelling fastest — 0.77 s of
## 3.30, at 6.6 m/s. The rest of the clip is the follow-through and the step back,
## which is why anything waiting for the throw waits for this and not for the end.
const THROW_RELEASE: float = 0.233

## Under this, a turn is not worth a clip.
##
## A character who plays a three second half-turn because the stick moved five
## degrees is a character who never does what they were told. Below it the body
## simply turns towards the heading at `TURN_SPEED`, which is what it always did.
const TURN_FLOOR: float = 1.05  # 60°

## How far a turn clip may be warped from the angle it was authored for.
##
## The clip is played at its own rate and the body is turned by the exact angle
## asked for, distributed along the clip's own yaw curve. Stretching it too far
## is what makes the feet pivot in a place the body is not turning through, so
## outside this band the nearest clip is used and the remainder is left to
## `TURN_SPEED` — a few degrees, under the turn, invisible.
const NARROWEST_WARP: float = 0.65
const WIDEST_WARP: float = 1.45


## Which clip to play and how fast.
class Motion:
	extends RefCounted

	## Empty when standing still.
	var clip: String = ""

	## Playback rate. One is the clip as it was authored.
	var rate: float = 1.0

	func is_moving() -> bool:
		return not clip.is_empty()


## Which turn clip serves an angle, and how much it has to be warped.
class Pivot:
	extends RefCounted

	## Empty when no clip should play — the angle is too small to be worth one.
	var clip: String = ""

	## What the clip delivers, in radians. Signed.
	var authored: float = 0.0

	## What the clip will be made to deliver, in radians. Signed, and equal to
	## the angle asked for unless that would have warped the clip past the band.
	var delivers: float = 0.0

	func is_turning() -> bool:
		return not clip.is_empty()

	## How much the clip's own rotation is scaled. One means the clip was
	## authored for exactly this turn.
	func warp() -> float:
		if absf(authored) <= 0.0:
			return 1.0
		return delivers / authored


## The gait for a ground speed.
##
## The nearest authored speed wins rather than a threshold between them. A
## threshold is a number somebody has to pick and re-pick every time a clip is
## added; nearest is the same rule however many gaits there are.
static func moving_at(speed: float) -> Motion:
	var motion: Motion = Motion.new()
	if speed <= STILL or LOOKS_RIGHT_AT.is_empty():
		return motion

	var best: String = ""
	var closest: float = INF
	for clip: String in LOOKS_RIGHT_AT:
		var apart: float = absf(speed - LOOKS_RIGHT_AT[clip])
		if apart < closest:
			closest = apart
			best = clip

	motion.clip = best
	motion.rate = rate_for(best, speed)
	return motion


## The playback rate that puts a gait at a speed, kept inside the band where a
## cadence still reads as human.
static func rate_for(clip: String, speed: float) -> float:
	if not LOOKS_RIGHT_AT.has(clip):
		return 1.0
	var authored: float = LOOKS_RIGHT_AT[clip]
	if authored <= 0.0:
		return 1.0
	return clampf(speed / authored, SLOWEST_RATE, FASTEST_RATE)


## How many gait cycles a second a speed calls for.
##
## Between the two authored speeds this interpolates the cadence, which is what
## keeps a blend of the two clips in step: both play one cycle in the same time,
## whatever mixture of them is on screen. `walk_cycle` and `run_cycle` are the
## clips' own lengths, read from the library rather than restated here.
static func cadence_for(speed: float, walk_cycle: float, run_cycle: float) -> float:
	if walk_cycle <= 0.0 or run_cycle <= 0.0:
		return 1.0

	var slow: float = LOOKS_RIGHT_AT[HumanoidClips.WALK]
	var fast: float = LOOKS_RIGHT_AT[HumanoidClips.RUN]
	var walking: float = 1.0 / walk_cycle
	var running: float = 1.0 / run_cycle

	if fast <= slow:
		return walking

	# Below the walk the line is followed downwards — somebody edging forward
	# takes slower steps, not walking-pace ones on the spot. Above the run it is
	# not: there is no faster gait to be heading towards, and a cadence
	# extrapolated off the end of two points is a number with nothing behind it.
	# What keeps the bottom honest is the rate band, applied where the rate is.
	var along: float = (speed - slow) / (fast - slow)
	return lerpf(walking, running, minf(along, 1.0))


## The turn clip for an angle, or nothing when the angle is too small for one.
##
## `turns` is what each clip actually delivers, in radians, signed — read off the
## clips themselves rather than restated here, so the arithmetic and the assets
## cannot drift apart. Measured, they are +90.0°, -102.6°, +176.1° and -175.1°:
## two of them fall short of the half turn they were ordered as and one overshoots
## its quarter turn by nearly thirteen degrees, which is why none is used at face
## value.
##
## The nearest authored angle **on the same side** wins: a turn one way is never
## served by a clip that goes the other, however close the magnitudes are, because
## the feet cross the other way and everybody can see it.
static func pivot_by(angle: float, turns: Dictionary[String, float]) -> Pivot:
	var pivot: Pivot = Pivot.new()
	if absf(angle) < TURN_FLOOR:
		return pivot

	var best: String = ""
	var closest: float = INF
	for clip: String in turns:
		var authored: float = turns[clip]
		if signf(authored) != signf(angle):
			continue
		var apart: float = absf(absf(angle) - absf(authored))
		if apart < closest:
			closest = apart
			best = clip

	if best.is_empty():
		return pivot

	# Warped to land on the angle exactly, unless that stretches the clip past
	# the band — outside it the feet pivot across ground the body is not turning
	# through. Then the clip delivers what it can and the remainder is left to the
	# ordinary turn, which is a few degrees underneath a turn already happening.
	var authored: float = turns[best]
	pivot.clip = best
	pivot.authored = authored
	pivot.delivers = clampf(angle / authored, NARROWEST_WARP, WIDEST_WARP) * authored
	return pivot


## Which way a body must be turned to face a grid direction.
##
## This model looks along **+Z** — measured from the rig, not assumed: its toes
## reach further along +Z than its ankles. So a body at yaw θ faces
## `(sin θ, 0, cos θ)`, and the yaw is the bearing.
static func yaw_of(direction: VltFacing.Direction) -> float:
	return yaw_towards(Vector2(VltFacing.DELTAS[direction]))


## The same, for a heading that is not one of four.
##
## Movement is omnidirectional and the body follows it exactly: quantising here
## would put the character's shoulders on a four-way grid its feet had already
## left.
static func yaw_towards(heading: Vector2) -> float:
	if heading.length_squared() <= 0.0:
		return 0.0
	return atan2(heading.x, heading.y)


## One frame of turning: towards the wanted yaw, never past it, never faster than
## a character can turn.
static func turned(from: float, towards: float, delta: float) -> float:
	if delta <= 0.0:
		return from
	return rotate_toward(from, towards, TURN_SPEED * delta)
