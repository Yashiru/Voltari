@tool
class_name VltMapOverlay
extends RefCounted

## What a map looks like to the rules, drawn where the rules think it is.
##
## The viewport shows models. The rules read shapes, painted cells and the edge
## of the terrain, and none of that was visible: a fence that stops nobody and a
## fence that stops you correctly look identical from above, and the only way to
## tell them apart was to run the game and walk into it.
##
## **Everything here is asked of the map** (decision 0073) rather than worked out
## again from the grids. An overlay that derived its own shapes would draw a
## hitbox nobody plays against — worse than drawing nothing, because it would be
## believed.
##
## Pure geometry and no state. Every function returns points in pairs, each pair
## one segment, in the map's own local space — which is the space a gizmo on the
## map node draws in. That is what makes all of this testable with no editor
## anywhere near it.
##
## ## One assumption, inherited rather than invented
##
## `VltWorldMap` reads its grids as though they sat at the map's own origin: it
## converts cells through `terrain` and compares the result against shapes built
## from `blocking`. This draws in the same space for the same reason, so a layer
## someone has moved shows up here as an overlay that has slid off its models —
## which is the correct thing for it to do. The alternative, quietly correcting
## for the transform, would hide a discrepancy the rules do not correct for.

## How far above the ground the flat parts sit, in metres. A line drawn exactly
## on the floor z-fights with it, and a diagnostic that flickers reads as a
## diagnostic that is broken.
const LIFT: float = 0.03

## How high a hitbox is drawn, in metres.
##
## The band the footprint was measured in, so what is drawn is what was measured.
## Drawing it shorter would invite the reading that the shape stops there, which
## is the one thing about the band that is worth seeing: what is above it was
## walked under, not walked into.
const BAND: float = VltFootprint.REACH

## How high a boundary tick stands, in metres. A flat outline is invisible
## edge-on, which is most of the time when looking across a map rather than down
## at it — the same lesson the placed-node gizmo already learned.
const TICK: float = 0.5

## Segments in a drawn circle. Sixteen reads as round at the size of a person and
## costs thirty-two points.
const ROUND: int = 16

## The four neighbours of a cell. Only the four: a boundary is made of sides, and
## a corner is where two sides meet rather than a side of its own.
const SIDES: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


## The shapes that stop you, each standing in the band it was measured in.
##
## This is the whole reason the overlay exists. Since decision 0072 an object
## blocks where its mesh is rather than where its cell is, which is correct and
## completely invisible — the difference between a post that owns its square
## metre and one that owns five centimetres of it cannot be seen at all.
static func hitboxes(map: VltWorldMap) -> PackedVector3Array:
	var lines: PackedVector3Array = PackedVector3Array()
	if map == null:
		return lines

	var ground: float = ground_of(map)
	for shape: VltFootprint in map.footprints():
		_prism(lines, shape.outline, ground)
	return lines


## The cells claimed whole, as a crossed square.
##
## Crossed rather than merely outlined, because an outlined cell is what a warp
## and a zone already look like. **The two things that stop you are not two
## answers to one question** and have to be told apart at a glance: this one is
## the ground itself being the obstacle, and no shape will ever be measured for
## it.
static func blocked(map: VltWorldMap) -> PackedVector3Array:
	var lines: PackedVector3Array = PackedVector3Array()
	if map == null or map.blocking == null:
		return lines

	var ground: float = ground_of(map)
	var half: float = map.cell_width() * 0.5
	var exists: Dictionary[Vector2i, bool] = cells_of(map.terrain)

	for cell: Vector3i in map.blocking.get_used_cells():
		var flat: Vector2i = Vector2i(cell.x, cell.z)
		# Beyond the terrain there is nothing to claim: off the map already stops
		# you, and `edges` draws that. A cross out there would say a second thing
		# is happening when only one is.
		if not exists.has(flat):
			continue
		# Open means what is painted here is a model, and a model's answer is its
		# shape — already drawn by `hitboxes`, to the centimetre.
		if map.is_open(flat):
			continue

		var middle: Vector2 = flat_of(map, flat)
		_square(lines, middle, half, ground + LIFT)
		_cross(lines, middle, half, ground + LIFT)
	return lines


## The boundary between the map and what is not the map.
##
## Off the map stops you exactly the way a wall does (`VltWorldMap`), and it is
## the only thing that stops you with nothing painted to show for it. Without
## this it cannot be seen at all — which is why a map needs no fence around it
## and why nobody can tell where the fence would have been.
static func edges(map: VltWorldMap) -> PackedVector3Array:
	if map == null or map.terrain == null:
		return PackedVector3Array()
	return _boundary(map, cells_of(map.terrain), ground_of(map), TICK)


## Where grass and leaves were sown, as the outline of each patch.
##
## A patch keeps its cells as a list on a node, so today the only way to see one
## is to select it and read a count. Two patches overlapping, or one stopping a
## cell short of where the lawn appears to stop, stay invisible until somebody
## goes looking — and the reason to go looking is that something already went
## wrong.
##
## Each patch is outlined on its own rather than merged, because two patches are
## two sets of settings and the seam between them is the thing worth seeing.
static func patches(map: VltWorldMap) -> PackedVector3Array:
	var lines: PackedVector3Array = PackedVector3Array()
	if map == null:
		return lines

	var ground: float = ground_of(map)
	for sown: Node in sown_under(map):
		# Read as an untyped array on purpose. A node whose script is not `@tool`
		# is held in the editor as a placeholder, which answers for its exported
		# properties and nothing else — so the value arrives without the element
		# type the class declares.
		var held: Array = sown.get("cells")
		var flat: Dictionary[Vector2i, bool] = {}
		for cell: Vector3i in held:
			flat[Vector2i(cell.x, cell.z)] = true
		lines.append_array(_boundary(map, flat, ground, 0.0))
	return lines


## How much room the player takes, drawn where the player appears.
##
## A disc at every warp and every rest point, because those are the two places
## somebody materialises rather than walks. A door opening into a gap narrower
## than the player is a map that traps them, and it looks perfectly fine until
## somebody arrives there.
##
## The radius is passed in rather than read here: this file has no business
## knowing how wide a person is, and the caller already does.
static func arrivals(map: VltWorldMap, radius: float) -> PackedVector3Array:
	var lines: PackedVector3Array = PackedVector3Array()
	if map == null or radius <= 0.0:
		return lines

	var ground: float = ground_of(map)
	for cell: Vector2i in _appearances(map):
		_circle(lines, flat_of(map, cell), radius, ground + LIFT)
	return lines


# --- what the map holds -------------------------------------------------------


## Every cell a grid holds, flattened. The overworld is one storey, so two cells
## sharing an (x, z) would be the same cell twice.
static func cells_of(grid: GridMap) -> Dictionary[Vector2i, bool]:
	var found: Dictionary[Vector2i, bool] = {}
	if grid == null:
		return found
	for cell: Vector3i in grid.get_used_cells():
		found[Vector2i(cell.x, cell.z)] = true
	return found


## Every patch of turf or foliage under a map.
##
## Found by walking rather than by a list on the map, because a patch is an
## ordinary node an author can group, rename or reparent, and a list would be a
## second place to keep correct.
##
## Typed as `Node` and read through `get`, so this file does not have to name two
## presentation classes to ask them the one question it has.
static func sown_under(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	if root == null:
		return found
	for child: Node in root.get_children():
		if child is TurfPatch or child is VltFoliagePatch:
			found.append(child)
		found.append_array(sown_under(child))
	return found


## The cells somebody can arrive on: warps and rest points.
##
## Both are read off the nodes as properties. A cast and a field do not run a
## script, so neither class has to be reachable from the editor for this to work
## — the placed-node gizmo has always read them this way.
static func _appearances(map: VltWorldMap) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for child: Node in map.get_children():
		var warp: VltWarp = child as VltWarp
		if warp != null:
			found.append(warp.cell)
			continue
		var rest: VltRestPoint = child as VltRestPoint
		if rest != null:
			found.append(rest.cell)
	return found


## The height the map's ground sits at, in its own space.
static func ground_of(map: VltWorldMap) -> float:
	if map == null:
		return 0.0
	return map.centre_of(Vector2i.ZERO).y


## The middle of a cell, flattened to the ground plane.
static func flat_of(map: VltWorldMap, cell: Vector2i) -> Vector2:
	var middle: Vector3 = map.centre_of(cell)
	return Vector2(middle.x, middle.z)


## What is painted on a map, as one number.
##
## A `GridMap` announces nothing when a cell changes, so the only way to notice a
## brush stroke is to look. This is what makes looking cheap enough to do several
## times a second: one integer to compare, against a set of shapes to rebuild.
##
## All three layers, because all three are drawn from. Item and orientation as
## well as presence, so repainting a cell with a different model counts as a
## change — the shape it contributes is a different shape.
##
## `TurfPatch` keeps a signature of its own for its own question, and also
## watches the transforms of the props beside the grid because a patch regrows
## around them. The two overlap and neither contains the other. A third caller is
## the moment to make it one thing; two is not.
static func signature_of(map: VltWorldMap) -> int:
	if map == null:
		return 0

	# An `Array` and not a packed one: only `Array` offers `hash`, and hashing the
	# whole thing in one call is what keeps this file free of a folding constant
	# that would be the second copy of `TurfPatch`'s.
	var parts: Array[int] = []
	for grid: GridMap in [map.terrain, map.blocking, map.decor]:
		if grid == null:
			# Counted rather than skipped: a layer that has just been unassigned
			# is a change, and silence about it would leave the overlay drawing
			# what used to be there.
			parts.append(0)
			continue
		var used: Array[Vector3i] = grid.get_used_cells()
		parts.append(used.hash())
		for cell: Vector3i in used:
			parts.append(grid.get_cell_item(cell))
			parts.append(grid.get_cell_item_orientation(cell))
	return parts.hash()


# --- drawing ------------------------------------------------------------------


## The outline of a set of cells: every side with nothing beyond it.
##
## Sides rather than a traced loop. A set of cells can be disjoint, ringed, or
## one cell wide, and a tracer needs an opinion about each of those. "A side with
## nothing next to it" is the boundary in all three cases and needs no opinion at
## all.
static func _boundary(
	map: VltWorldMap, cells: Dictionary[Vector2i, bool], ground: float, tick: float
) -> PackedVector3Array:
	var lines: PackedVector3Array = PackedVector3Array()
	var half: float = map.cell_width() * 0.5

	for cell: Vector2i in cells:
		var middle: Vector2 = flat_of(map, cell)
		for side: Vector2i in SIDES:
			if cells.has(cell + side):
				continue

			var out: Vector2 = Vector2(float(side.x), float(side.y)) * half
			var along: Vector2 = Vector2(float(side.y), float(-side.x)) * half
			var one: Vector2 = middle + out + along
			var two: Vector2 = middle + out - along

			lines.append(_point(one, ground + LIFT))
			lines.append(_point(two, ground + LIFT))
			if tick <= 0.0:
				continue
			# Standing up at both ends, so the boundary reads from across the map
			# and not only from directly above it.
			lines.append(_point(one, ground + LIFT))
			lines.append(_point(one, ground + tick))
			lines.append(_point(two, ground + LIFT))
			lines.append(_point(two, ground + tick))

	return lines


## A footprint as it was measured: its outline on the ground, the same outline at
## the top of the band, and an upright at every corner joining them.
static func _prism(lines: PackedVector3Array, outline: PackedVector2Array, ground: float) -> void:
	if outline.size() < 3:
		return

	for index: int in range(outline.size()):
		var here: Vector2 = outline[index]
		var next: Vector2 = outline[(index + 1) % outline.size()]

		lines.append(_point(here, ground + LIFT))
		lines.append(_point(next, ground + LIFT))
		lines.append(_point(here, ground + BAND))
		lines.append(_point(next, ground + BAND))
		lines.append(_point(here, ground + LIFT))
		lines.append(_point(here, ground + BAND))


static func _square(lines: PackedVector3Array, middle: Vector2, half: float, y: float) -> void:
	var corners: Array[Vector2] = [
		middle + Vector2(-half, -half), middle + Vector2(half, -half),
		middle + Vector2(half, half), middle + Vector2(-half, half),
	]
	for index: int in range(corners.size()):
		lines.append(_point(corners[index], y))
		lines.append(_point(corners[(index + 1) % corners.size()], y))


static func _cross(lines: PackedVector3Array, middle: Vector2, half: float, y: float) -> void:
	lines.append(_point(middle + Vector2(-half, -half), y))
	lines.append(_point(middle + Vector2(half, half), y))
	lines.append(_point(middle + Vector2(half, -half), y))
	lines.append(_point(middle + Vector2(-half, half), y))


static func _circle(lines: PackedVector3Array, middle: Vector2, radius: float, y: float) -> void:
	for index: int in range(ROUND):
		var here: float = TAU * float(index) / float(ROUND)
		var next: float = TAU * float(index + 1) / float(ROUND)
		lines.append(_point(middle + Vector2(cos(here), sin(here)) * radius, y))
		lines.append(_point(middle + Vector2(cos(next), sin(next)) * radius, y))


## A point on the ground plane, lifted. Everything above works in (x, z) and
## gains its height here, so no function has to carry a height it does not use.
static func _point(flat: Vector2, y: float) -> Vector3:
	return Vector3(flat.x, y, flat.y)
