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

## The smallest a prop may come out of a spread, as a multiple of its model.
##
## Not zero: a prop scaled to nothing draws nothing, blocks nothing and cannot be
## clicked, so it is invisible in every sense including to the author looking for
## what went wrong. A spread wider than the size it varies is a typo, and this is
## where it stops.
const SMALLEST: float = 0.01

## **What is placed is not held here.** The item comes from the palette the
## author already has open, read at the moment of the click — the same reasoning
## that made sowing read the `GridMap` editor's own cell selection rather than
## offer a second way to choose cells. A copy kept here would be a second answer
## to "which model", and the two would disagree the first time somebody changed
## one of them.
##
## What is held here is how the next prop is turned and sized, which the palette
## has no opinion about.

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


func _init(seed_with: int = 0) -> void:
	if seed_with != 0:
		_random.seed = seed_with


## Where and how the next prop stands, given a point on the ground.
##
## The point is the origin: a model is authored standing on its own origin (the
## tile library leaves every one of them that way), so putting the origin on the
## ground is what makes a prop stand on it rather than sink into it.
func next_at(point: Vector3) -> Transform3D:
	var angle: float = deg_to_rad(turn + _spread(turn_spread))
	var scale: float = maxf(size + _spread(size_spread), SMALLEST)
	return Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * scale), point)


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
