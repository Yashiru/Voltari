@tool
class_name VltPropBrush
extends RefCounted

## What the next prop will look like when it lands.
##
## Held apart from the gesture that places it, because this is the half that
## carries numbers. A viewport click is not somewhere an assertion can reach; a
## turn, a size and the spread around each are exactly the kind of arithmetic
## that is wrong quietly — a scatter that never varies, or one that occasionally
## produces a prop scaled to nothing, looks fine until somebody looks closely at
## the right prop.
##
## ## Why the turn is only about the vertical
##
## Free rotation on three axes was weighed and declined. The footprint maths
## handles any transform, so this is not a limit the geometry imposes — it is
## what a brush should offer: everything a prop is placed on is the ground, and a
## tilted fence post is a mistake far more often than it is a decision. Tilting
## one afterwards in the inspector is still possible, still measured correctly,
## and still reported by the validator as the unusual thing it is.
##
## ## Why the size is one number
##
## A prop scaled differently along x and z is a squashed prop, which is a thing
## somebody occasionally wants and never wants *by accident* — which is what a
## scatter with three independent spreads would produce. The inspector does it
## deliberately, and the footprint follows it there too.

## How tall a model has to stand, in metres, before a prop made of it blocks.
##
## **A road is not a wall, and the difference is measurable.** Paths, slabs,
## carpets, painted markings and puddles are laid on the ground in numbers, and
## having to say "this one stops nobody" for each of them is the kind of chore an
## author stops doing — after which the map has hitboxes nobody meant.
##
## Fifteen centimetres is above anything laid flat and below any kerb, step or
## threshold somebody would expect to be stopped by. It is measured on the model
## **as placed**, so a slab scaled up until it is genuinely a step blocks like
## one, and the same model laid flat does not.
##
## A default and nothing more: the answer is written onto the prop, where it can
## be read and changed. Nothing re-derives it later, so a prop an author has
## decided about keeps that decision even if the rule here changes.
const STANDS: float = 0.15

## The smallest a prop may come out of a spread, as a multiple of its model.
##
## Not zero: a prop scaled to nothing draws nothing, blocks nothing and cannot be
## clicked, so it is invisible in every sense including to the author looking for
## what went wrong. A spread wider than the size it varies is a typo, and this is
## where it stops.
const SMALLEST: float = 0.01

## Which way a prop faces, in degrees about the vertical, and how far either side
## of that it may land.
##
## A spread either side rather than a low and a high: an author thinks "roughly
## this way, give or take", and two numbers that can be the wrong way round are
## two numbers that will one day be the wrong way round.
var turn: float = 0.0
var turn_spread: float = 0.0

## How big, as a multiple of the model, and how far either side of that.
var size: float = 1.0
var size_spread: float = 0.0

## The source of the variation.
##
## An instance rather than the global `randf_range`, so that a seed makes a run
## repeatable — which is what lets the spread be tested at all, and what would let
## a scattered row be laid down twice the same way if anybody ever wants that.
var _random: RandomNumberGenerator = RandomNumberGenerator.new()


## Which item of the palette the next prop is made of.
##
## Held here after all. The first attempt read it from the `GridMap` palette at
## the moment of the click, so that there was one place a model was chosen — and
## the argument was sound until the consequence arrived: reading that palette
## means being in the engine's paint mode, which fights for the same click and
## draws its own preview of the unturned, unscaled model. A source that imposes a
## mode that contradicts the gesture is not a source worth keeping.
var item: int = -1

## The turn and size the next prop will get, drawn once and held until it lands.
##
## **Stable on purpose.** A preview has to show what is about to happen, and one
## that redrew its random numbers every frame would spin and pulse under the
## cursor while promising nothing. So the values are decided when they are first
## asked for and kept until `placed` or `restyled` says they are spent.
var _turn_now: float = 0.0
var _size_now: float = 1.0
var _drawn: bool = false


func _init(seed_with: int = 0) -> void:
	if seed_with != 0:
		_random.seed = seed_with


## Where and how the next prop stands, given a point on the ground.
##
## The point is the origin: a model is authored standing on its own origin (the
## tile library leaves every one of them that way), so putting the origin on the
## ground is what makes a prop stand on it rather than sink into it.
##
## Asked twice without a placement in between, it answers the same thing. That is
## the preview's contract, and it is why the variation is drawn here rather than
## per call.
## `fit` is a per-axis factor applied before the size — what it takes to make the
## model fill the grid, or `ONE` to leave it at the size it was authored. Kept as
## an argument rather than a field because only the caller has the model to
## measure, and a copy of the answer here would be one more thing to keep current.
func next_at(point: Vector3, fit: Vector3 = Vector3.ONE) -> Transform3D:
	if not _drawn:
		_draw()

	# **Turned after being scaled, not before.** `Basis.scaled` multiplies in the
	# parent's axes, so a non-cube fit applied that way would stretch a prop along
	# whichever world axis it happened to be facing. Written as a product, the
	# scale is the model's own and the turn is around it — which is also what the
	# inspector then shows as the node's scale and rotation.
	return Transform3D(
		Basis(Vector3.UP, deg_to_rad(_turn_now)) * Basis.from_scale(fit * _size_now), point
	)


## The pending prop has landed; the one after it is a fresh draw.
func placed() -> void:
	_drawn = false


## A setting changed, so whatever was pending is out of date.
##
## Without this the preview would keep showing the old numbers until something
## was placed, which is the one moment an author is definitely looking at it.
func restyled() -> void:
	_drawn = false


## Whether a prop standing this tall blocks, by default.
##
## Taller than the threshold rather than as tall: something exactly the height of
## a kerb is the case somebody laid flat on purpose, and the friendlier mistake
## is the one that lets them walk.
static func blocks_at(height: float) -> bool:
	return height > STANDS


func _draw() -> void:
	_turn_now = turn + _spread(turn_spread)
	_size_now = maxf(size + _spread(size_spread), SMALLEST)
	_drawn = true


## Whether the brush has a model to lay down.
func ready_to_paint() -> bool:
	return item >= 0


## A number somewhere in ±`either_way`, or exactly zero when there is no spread.
##
## Exactly zero matters: a brush set to no variation must place identical props,
## and a random draw from an empty range is not guaranteed by contract to be the
## same number every time.
func _spread(either_way: float) -> float:
	if is_zero_approx(either_way):
		return 0.0
	var reach: float = absf(either_way)
	return _random.randf_range(-reach, reach)
