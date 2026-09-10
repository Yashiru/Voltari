class_name WalkerGait
extends RefCounted

## How fast a character's legs should move, and which way it should be turned.
##
## Pure arithmetic, no nodes. It exists because the numbers underneath it are
## **measured** rather than chosen, and a measurement nobody can re-run is an
## assertion. `tools/characters/measure_gaits.gd` prints them; this is where they
## are used.
##
## ## What an in-place clip can and cannot tell you
##
## The clips carry no root motion, so the ground speed they imply cannot be read
## off them directly: the foot's travel relative to the body is a **compressed**
## stride, which is what every in-place clip has. What *is* honest is the
## **cadence** — how often a foot lands — and from a cadence and a step length
## proportional to the character's height, a speed follows.
##
## That is where `LOOKS_RIGHT_AT` comes from, and it is why the world moves at
## the speed the animation was authored for rather than the other way round.

## The clip that plays when nothing else does.
const IDLE_CLIP: String = "Listening_Gesture"

## The speed each gait was authored for, in metres per second.
##
## Measured, and re-measurable. `Running` at 169 steps a minute with a 1.28 m
## step — three quarters of this character's height, which is what a running step
## is — comes to 3.6 m/s. Playing it there is exactly the cadence the animator
## made, at a rate of one.
const LOOKS_RIGHT_AT: Dictionary[String, float] = {
	"Walking": 1.47,
	"Running": 3.60,
}

## How far the playback may be pushed from what a gait was authored for.
##
## Outside this the cadence stops being human: a run at twice the rate is 340
## steps a minute, which no amount of correct footfall makes look like running.
## Inside it, the error is a foot that slides — which every game has and nobody
## sees.
const SLOWEST_RATE: float = 0.80
const FASTEST_RATE: float = 1.25

## How fast a character turns, in radians a second. A quarter turn takes about a
## tenth of a second, which is under one step: the turn is finished before the
## walk that follows it starts, and it is never what you are waiting for.
const TURN_SPEED: float = 14.0

## Below this a character is standing still, whatever the arithmetic says.
const STILL: float = 0.01


## Which clip to play and how fast.
class Motion:
	extends RefCounted

	## Empty when standing still.
	var clip: String = ""

	## Playback rate. One is the clip as it was authored.
	var rate: float = 1.0

	func is_moving() -> bool:
		return not clip.is_empty()


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


## Which way a body must be turned to face a grid direction.
##
## This model looks along **+Z** — measured from the rig, not assumed: its toes
## reach further along +Z than its ankles. So a body at yaw θ faces
## `(sin θ, 0, cos θ)`, and the yaw is the bearing.
static func yaw_of(direction: VltFacing.Direction) -> float:
	var delta: Vector2i = VltFacing.DELTAS[direction]
	return atan2(float(delta.x), float(delta.y))


## One frame of turning: towards the wanted yaw, never past it, never faster than
## a character can turn.
static func turned(from: float, towards: float, delta: float) -> float:
	if delta <= 0.0:
		return from
	return rotate_toward(from, towards, TURN_SPEED * delta)
