class_name BattleStaging
extends RefCounted

## Where the two creatures stand and where the camera watches from (spec 17).
##
## Pure arithmetic, no nodes. It exists because the alternative is four numbers
## tuned against a screenshot: change the separation and the camera is wrong,
## change the creature height and the framing is wrong, and nothing says so
## until somebody looks.
##
## **Everything is derived.** The seats come from a separation and an angle; the
## camera comes from the seats, the creature height and the camera's own field of
## view. Move any of them and the rest follows.
##
## The one thing that cannot be derived is which way a model faces. These models
## look along **+Z**, so a body turned to yaw θ faces `(sin θ, 0, cos θ)`. That is
## a fact about the art, stated once, here.

## How far apart the two stand, in metres.
const SEPARATION: float = 2.4

## How far the line between them is turned away from screen-right.
##
## Zero would put them side by side across the frame, which reads as a diagram.
## Ninety would put one exactly behind the other. In between, the near one sits
## low and left and the far one high and right — and the depth is what makes one
## of them yours.
const SLANT_DEGREES: float = 38.0

## How far above the horizontal the camera looks down.
const PITCH_DEGREES: float = 20.0

## How far off your creature's shoulder the camera stands.
##
## Zero puts it exactly behind you, where you hide the other one. Ninety puts it
## side-on to the fight, which is where it was and why the two of you read as a
## line-up rather than as facing each other. In between is over the shoulder:
## your creature low and left, the other across the frame from it.
const SHOULDER_DEGREES: float = 24.0

## How much wider than the strict fit to frame. One would put the creatures
## exactly on the edges of the screen.
const MARGIN: float = 1.15

## How wide a creature is assumed to be, relative to its height. Only used to
## keep shoulders off the edge of the frame; nothing depends on it being right.
const WIDTH_RATIO: float = 0.9

## What a camera falls back to when it reports nothing usable.
const DEFAULT_FOV: float = 75.0

## The side that stands nearest the camera.
const NEAR_SIDE: int = 0

## How far behind their creature the trainer stands, in metres.
##
## Small on purpose. The camera watches over the near creature's shoulder, so
## anything put *behind* that creature is put in front of the lens: at a metre
## the trainer fills a third of the frame, and at two the camera has to pull so
## far back that both creatures become thumbnails. Beside is where a person fits.
const TRAINER_BEHIND: float = 0.35

## How far to the side of their creature the trainer stands.
##
## **Away from the camera's shoulder, not towards it.** The camera stands off the
## near creature's right, so a trainer put on the same side would be under the
## lens and would hide the creature the player is watching.
##
## This is the one that carries the separation, and it is roughly a creature's
## own height: near enough to read as its trainer, far enough not to stand on it.
const TRAINER_ASIDE: float = 1.35


## Where one side stands. Mirror images through the origin, so the pair is always
## centred whatever the separation.
static func seat(
	side: int, separation: float = SEPARATION, slant_degrees: float = SLANT_DEGREES
) -> Vector3:
	var slant: float = deg_to_rad(slant_degrees)
	# Turning screen-right by the slant: +X leans towards -Z as the angle grows.
	var axis: Vector3 = Vector3(cos(slant), 0.0, -sin(slant))
	var half: float = maxf(separation, 0.0) * 0.5
	return axis * (half if side != NEAR_SIDE else -half)


## Where the trainer stands: behind their own creature, off its far shoulder.
##
## Derived from the seats like everything else here, so it follows the separation
## and the slant rather than being a transform somebody typed in once. The
## creature stays the thing in the middle of the frame; the trainer is at its
## edge, which is the whole reason they are not simply given a third seat.
static func trainer_seat(
	separation: float = SEPARATION,
	slant_degrees: float = SLANT_DEGREES,
	behind: float = TRAINER_BEHIND,
	aside: float = TRAINER_ASIDE
) -> Vector3:
	var near: Vector3 = seat(NEAR_SIDE, separation, slant_degrees)
	var forward: Vector3 = towards_the_foe(separation, slant_degrees)
	var to_the_right: Vector3 = forward.cross(Vector3.UP).normalized()
	return near - forward * behind - to_the_right * aside


## The unit direction from the near side to the far one: the fight's own axis.
static func towards_the_foe(
	separation: float = SEPARATION, slant_degrees: float = SLANT_DEGREES
) -> Vector3:
	var along: Vector3 = (
		seat(NEAR_SIDE + 1, separation, slant_degrees)
		- seat(NEAR_SIDE, separation, slant_degrees)
	)
	along.y = 0.0
	if along.length_squared() <= 0.0:
		# Both on the same spot. Any direction is as wrong as any other, and this
		# one at least matches what the camera falls back to.
		return Vector3(0.0, 0.0, -1.0)
	return along.normalized()


## The yaw that turns a body at `from` to look at `to`.
##
## `atan2(x, z)` rather than the usual `atan2(z, x)` because these models face
## +Z: a body at yaw θ looks along `(sin θ, 0, cos θ)`, so the yaw *is* the
## bearing. Two bodies given each other's seat therefore face each other, whatever
## the seats are — which is the property that stops this drifting when the
## staging is retuned.
static func yaw_towards(from: Vector3, to: Vector3) -> float:
	var along: Vector3 = to - from
	if is_zero_approx(along.x) and is_zero_approx(along.z):
		return 0.0
	return atan2(along.x, along.z)


## The middle of what has to be in frame.
##
## Between the two creatures, at half their height — and half way to the trainer
## when there is one, because a camera that framed everything and looked at the
## pair would put the fight in a corner and the empty half of the field in the
## middle. Passing zero for `trainer_height` leaves them out, which is what a
## stage with nobody standing there wants.
static func centre(
	height: float,
	trainer_height: float = 0.0,
	separation: float = SEPARATION,
	slant_degrees: float = SLANT_DEGREES
) -> Vector3:
	var pair: Vector3 = Vector3(0.0, maxf(height, 0.0) * 0.5, 0.0)
	if trainer_height <= 0.0:
		return pair

	var person: Vector3 = trainer_seat(separation, slant_degrees)
	person.y = trainer_height * 0.5
	return (pair + person) * 0.5


## The radius of the sphere that holds everything that has to be seen.
##
## A sphere rather than a box because the camera may end up anywhere around it,
## and a sphere is the only shape whose silhouette does not depend on that.
##
## **The trainer counts.** They stand further from the middle than either creature
## and are taller than both, so a radius that ignored them would frame the fight
## perfectly and cut the player in half. Passing zero for `trainer_height` leaves
## them out, which is what a stage with nobody standing there wants.
static func framing_radius(
	height: float,
	separation: float = SEPARATION,
	width_ratio: float = WIDTH_RATIO,
	trainer_height: float = 0.0,
	slant_degrees: float = SLANT_DEGREES
) -> float:
	var tall: float = maxf(height, 0.0)
	var middle: Vector3 = centre(tall, trainer_height, separation, slant_degrees)

	var widest: float = 0.0
	for side: int in [NEAR_SIDE, NEAR_SIDE + 1]:
		widest = maxf(
			widest, _reach(seat(side, separation, slant_degrees), tall, middle, width_ratio)
		)

	if trainer_height > 0.0:
		widest = maxf(
			widest,
			_reach(
				trainer_seat(separation, slant_degrees), trainer_height, middle, width_ratio
			)
		)
	return widest


## How far one body reaches from the middle of the frame.
##
## Its far shoulder at the top of its head, and the same at its feet: the middle
## is above the ground, so for anything short the ankles are further away than the
## hair.
static func _reach(
	standing: Vector3, tall: float, middle: Vector3, width_ratio: float
) -> float:
	var half_wide: float = maxf(tall, 0.0) * maxf(width_ratio, 0.0) * 0.5
	var head: Vector3 = Vector3(standing.x, maxf(tall, 0.0), standing.z) - middle
	var feet: Vector3 = Vector3(standing.x, 0.0, standing.z) - middle
	return maxf(head.length(), feet.length()) + half_wide


## How far back the camera has to be for a sphere of that radius to fit.
##
## `r / sin(fov / 2)` is the exact distance at which a sphere subtends the whole
## field of view. The margin is what keeps it off the edges.
static func distance_for(
	radius: float, fov_degrees: float, margin: float = MARGIN
) -> float:
	var fov: float = fov_degrees if fov_degrees > 0.0 and fov_degrees < 180.0 else DEFAULT_FOV
	var half: float = sin(deg_to_rad(fov) * 0.5)
	if half <= 0.0:
		return maxf(radius, 0.0)
	return maxf(radius, 0.0) / half * maxf(margin, 1.0)


## Where the camera sits: over your creature's shoulder, raised by the pitch, far
## enough back that both fit.
##
## **Placed along the fight's own axis, not the world's.** A camera on +Z watches
## a fight that runs diagonally *from the side*, and the two creatures read as a
## line-up however carefully they are turned towards each other. Built from the
## seats, it is behind yours by construction whatever the slant is.
static func eye(
	height: float,
	fov_degrees: float,
	separation: float = SEPARATION,
	pitch_degrees: float = PITCH_DEGREES,
	margin: float = MARGIN,
	shoulder_degrees: float = SHOULDER_DEGREES,
	slant_degrees: float = SLANT_DEGREES,
	trainer_height: float = 0.0
) -> Vector3:
	var away: float = distance_for(
		framing_radius(height, separation, WIDTH_RATIO, trainer_height, slant_degrees),
		fov_degrees,
		margin
	)
	var direction: Vector3 = shoulder(pitch_degrees, shoulder_degrees, separation, slant_degrees)
	return centre(height, trainer_height, separation, slant_degrees) + direction * away


## The unit direction from the middle of the fight to the camera.
##
## Composed rather than rotated by a signed angle: "behind" and "to the right"
## are both read off the fight's own axis, so neither depends on which way the
## slant happens to lean. A rotation by a signed yaw would put the camera on the
## wrong shoulder the day somebody made the slant negative.
static func shoulder(
	pitch_degrees: float = PITCH_DEGREES,
	shoulder_degrees: float = SHOULDER_DEGREES,
	separation: float = SEPARATION,
	slant_degrees: float = SLANT_DEGREES
) -> Vector3:
	var forward: Vector3 = towards_the_foe(separation, slant_degrees)

	# Looking along `forward`, the camera's own right — the same convention Godot
	# uses for a camera, which looks along -Z with +X to its right.
	var to_the_right: Vector3 = forward.cross(Vector3.UP).normalized()
	var off: float = deg_to_rad(shoulder_degrees)
	var level: Vector3 = (-forward * cos(off) + to_the_right * sin(off)).normalized()

	var pitch: float = deg_to_rad(pitch_degrees)
	return (level * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


## Where the camera looks. The middle of what is drawn, so neither creature is
## favoured — the depth already says which one is yours.
static func target(
	height: float,
	trainer_height: float = 0.0,
	separation: float = SEPARATION,
	slant_degrees: float = SLANT_DEGREES
) -> Vector3:
	return centre(height, trainer_height, separation, slant_degrees)
