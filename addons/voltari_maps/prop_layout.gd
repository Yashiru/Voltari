@tool
class_name VltPropLayout
extends RefCounted

## Tidying a handful of props that are nearly where they should be.
##
## A palisade placed by eye is eight posts on eight slightly different lines, and
## the fix is not to place them again. These are the two gestures that do it, and
## they are arithmetic rather than gestures — which is why they are here, apart
## from the buttons that call them, and tested.
##
## **Positions in, positions out.** Nothing here touches a node, reads a
## selection or knows about an editor. That is what lets the awkward cases — one
## prop, none, several on the same spot — be asked directly instead of discovered
## by clicking.


## Which way the points vary least, which is the line they are nearly on.
##
## Chosen rather than asked for, because an author selecting a row of posts has
## already said which way it runs by where they put them. Asking again would be a
## second chance to say something they have already said, and to say it
## differently.
##
## Ties go to `x`. A perfect square of four has no row in it and any answer is
## arbitrary; what matters is that the arbitrary one is always the same.
static func line_of(points: Array[Vector3]) -> Vector3:
	if points.size() < 2:
		return Vector3.RIGHT

	var low: Vector3 = points[0]
	var high: Vector3 = points[0]
	for point: Vector3 in points:
		low = Vector3(minf(low.x, point.x), minf(low.y, point.y), minf(low.z, point.z))
		high = Vector3(maxf(high.x, point.x), maxf(high.y, point.y), maxf(high.z, point.z))

	return Vector3.RIGHT if high.x - low.x >= high.z - low.z else Vector3.BACK


## The same points, moved onto one line.
##
## Onto their own average across the line, rather than onto the first of them:
## the average is the answer that moves everything least, and "first" depends on
## selection order, which is not something an author chose or can see.
##
## Heights are left alone. A row of posts on a slope is a row of posts on a slope,
## and levelling one would be a second gesture nobody asked for — `dropped` in
## `VltMapPlacement` is where height belongs.
static func aligned(points: Array[Vector3]) -> Array[Vector3]:
	if points.size() < 2:
		return points.duplicate()

	var along: Vector3 = line_of(points)
	var across: bool = along.is_equal_approx(Vector3.RIGHT)

	var total: float = 0.0
	for point: Vector3 in points:
		total += point.z if across else point.x
	var middle: float = total / float(points.size())

	var moved: Array[Vector3] = []
	for point: Vector3 in points:
		moved.append(
			Vector3(point.x, point.y, middle) if across else Vector3(middle, point.y, point.z)
		)
	return moved


## The same points, evenly spaced between the two outermost of them.
##
## The ends stay where they are and everything between them is redistributed,
## which is what makes this repeatable: running it twice changes nothing the
## second time, and an author who liked where the row started and ended keeps
## both.
##
## Ordered along the line first, so selection order cannot shuffle a row. Two
## points are already evenly spaced, and so is one.
static func spread(points: Array[Vector3]) -> Array[Vector3]:
	if points.size() < 3:
		return points.duplicate()

	var along: Vector3 = line_of(points)
	var ordered: Array[Vector3] = points.duplicate()
	if along.is_equal_approx(Vector3.RIGHT):
		ordered.sort_custom(_by_x)
	else:
		ordered.sort_custom(_by_z)

	var first: Vector3 = ordered[0]
	var last: Vector3 = ordered[ordered.size() - 1]
	var steps: float = float(ordered.size() - 1)

	var moved: Array[Vector3] = []
	for index: int in range(ordered.size()):
		var part: float = float(index) / steps
		# Only the ground axes are interpolated: a height somebody set on one prop
		# is theirs, and sliding it towards its neighbours' would be this gesture
		# quietly doing a different one.
		moved.append(Vector3(
			lerpf(first.x, last.x, part), ordered[index].y, lerpf(first.z, last.z, part)
		))
	return moved


static func _by_x(one: Vector3, two: Vector3) -> bool:
	return one.x < two.x


static func _by_z(one: Vector3, two: Vector3) -> bool:
	return one.z < two.z
