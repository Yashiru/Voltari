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


## The middle of what has to be in frame: between the two, at half their height.
static func centre(height: float) -> Vector3:
	return Vector3(0.0, maxf(height, 0.0) * 0.5, 0.0)


## The radius of the sphere that holds both creatures.
##
## A sphere rather than a box because the camera may end up anywhere around it,
## and a sphere is the only shape whose silhouette does not depend on that.
static func framing_radius(
	height: float, separation: float = SEPARATION, width_ratio: float = WIDTH_RATIO
) -> float:
	var tall: float = maxf(height, 0.0)
	var half_apart: float = maxf(separation, 0.0) * 0.5
	var half_wide: float = tall * maxf(width_ratio, 0.0) * 0.5
	# The furthest point of either creature from the centre: its far shoulder at
	# the top of its head.
	return sqrt(half_apart * half_apart + (tall * 0.5) * (tall * 0.5)) + half_wide


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
	slant_degrees: float = SLANT_DEGREES
) -> Vector3:
	var away: float = distance_for(framing_radius(height, separation), fov_degrees, margin)
	var direction: Vector3 = shoulder(pitch_degrees, shoulder_degrees, separation, slant_degrees)
	return centre(height) + direction * away


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
	var near: Vector3 = seat(NEAR_SIDE, separation, slant_degrees)
	var far: Vector3 = seat(NEAR_SIDE + 1, separation, slant_degrees)

	var forward: Vector3 = (far - near)
	forward.y = 0.0
	if forward.length_squared() <= 0.0:
		# Both on the same spot. Any direction frames it equally badly, and this
		# one at least matches what the camera used to do.
		forward = Vector3(0.0, 0.0, -1.0)
	forward = forward.normalized()

	# Looking along `forward`, the camera's own right — the same convention Godot
	# uses for a camera, which looks along -Z with +X to its right.
	var to_the_right: Vector3 = forward.cross(Vector3.UP).normalized()
	var off: float = deg_to_rad(shoulder_degrees)
	var level: Vector3 = (-forward * cos(off) + to_the_right * sin(off)).normalized()

	var pitch: float = deg_to_rad(pitch_degrees)
	return (level * cos(pitch) + Vector3.UP * sin(pitch)).normalized()


## Where the camera looks. The centre of the pair, so neither is favoured — the
## depth already says which one is yours.
static func target(height: float) -> Vector3:
	return centre(height)
