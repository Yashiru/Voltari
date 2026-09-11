@tool
class_name VltMapBlocking
extends RefCounted

## What a model in the blocking layer actually stops you walking into.
##
## A `GridMap` cell holds one item, and `is_walkable` asks one question of one
## cell (spec 14, section 2). A house is five cells wide, so painting it blocked
## exactly one of them and the player walked through the other twenty-four.
##
## **The footprint is painted, not derived.** Deriving it at runtime would read
## better here and be worse everywhere else: a rule that lives in the geometry
## cannot be corrected, and the first thing anybody wants is a doorway through a
## house that the model does not have. Painted cells can be erased. So this fills
## them in and then leaves them alone — the map goes on being the authority on
## itself, the validator goes on reading it, and spec 14 section 1 is untouched
## because nothing new decides anything at runtime.
##
## **Below two metres**, because that is roughly the character and the question is
## what they would walk into. A canopy over a path is not in the way and neither
## is the eave of a roof; the trunk and the wall are. Taken from the geometry in
## that band rather than from the whole bounding box, which for a palm tree would
## block the whole clearing it shades.

## How high off the ground still counts as being in the way, in world metres.
##
## The character is about this tall. Higher than that and a model is something you
## walk under, which is a thing maps are made of — an arch, a balcony, a branch.
const REACH: float = 2.0

## How much of a cell a model has to cover before that cell is blocked, as a
## fraction of the cell.
##
## Not zero. A wall that overhangs its neighbour by a millimetre would otherwise
## take that whole cell, and a corridor drawn exactly two cells wide would admit
## nobody. A twentieth is below anything an author would draw on purpose and well
## above what the edge of a mesh lands on by accident.
const GRIP: float = 0.05

## The one item the tile library makes rather than reads: it draws nothing, so a
## cell can be blocked without a model appearing on it.
const BLOCKER: String = "_blocked"


## The cells a model covers, including the one it is painted on.
##
## In the layer's own cell coordinates, at the host's own height — a prop painted
## on a raised cell blocks around itself up there, not on the ground.
## `was` names the item when the caller knows it and the cell no longer does —
## taking back the cells a model held needs its footprint after it has gone.
static func footprint(
	grid: GridMap, cell: Vector3i, below: float = REACH,
	was: int = GridMap.INVALID_CELL_ITEM
) -> Array[Vector3i]:
	var covered: Array[Vector3i] = []
	if grid.mesh_library == null:
		return covered

	var item: int = was if was != GridMap.INVALID_CELL_ITEM else grid.get_cell_item(cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return covered

	var mesh: Mesh = grid.mesh_library.get_item_mesh(item)
	if mesh == null:
		return covered

	# The mesh is in the artist's units and the grid draws it scaled, so the band
	# has to be converted the other way rather than the geometry converted into
	# world space. `cell_scale` is never zero in practice and a zero here would
	# divide, so it is floored rather than trusted.
	var scale: float = maxf(grid.cell_scale, 0.001)
	var box: Rect2 = extent(mesh, below / scale)
	if box.size.x <= 0.0 and box.size.y <= 0.0:
		return covered

	# `Rect2` is the flat footprint: its `y` is the world's `z`. Named here once
	# rather than at every use.
	var middle: Vector3 = grid.map_to_local(cell)
	var low: Vector2 = Vector2(middle.x, middle.z) + box.position * scale
	var size: Vector2 = box.size * scale

	var step: Vector2 = Vector2(maxf(grid.cell_size.x, 0.001), maxf(grid.cell_size.z, 0.001))
	var inset: Vector2 = step * GRIP
	var first: Vector2i = _cell_of(grid, low + inset)
	var last: Vector2i = _cell_of(grid, low + size - inset)

	for x: int in range(mini(first.x, last.x), maxi(first.x, last.x) + 1):
		for z: int in range(mini(first.y, last.y), maxi(first.y, last.y) + 1):
			covered.append(Vector3i(x, cell.y, z))

	return covered


## The cell a flat position falls in. Through the grid's own conversion rather
## than by dividing, so centring and cell size stay its business and not a second
## copy of its arithmetic here.
static func _cell_of(grid: GridMap, at: Vector2) -> Vector2i:
	var cell: Vector3i = grid.local_to_map(Vector3(at.x, 0.0, at.y))
	return Vector2i(cell.x, cell.z)


## The flat extent of the part of a mesh that is below a height, in the mesh's own
## units. `x` and `y` of the rectangle are the world's `x` and `z`.
##
## Measured from the vertices rather than from the bounding box: the box of a palm
## is the box of its fronds, and blocking a whole clearing because something
## shades it is exactly the mistake this exists to avoid.
##
## An empty rectangle when nothing is low enough, which is a model that is
## entirely overhead and should stop nobody.
static func extent(mesh: Mesh, below: float) -> Rect2:
	var lowest: Vector2 = Vector2.ZERO
	var highest: Vector2 = Vector2.ZERO
	var found: bool = false

	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if typeof(arrays[Mesh.ARRAY_VERTEX]) != TYPE_PACKED_VECTOR3_ARRAY:
			continue
		@warning_ignore("unsafe_cast")
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array

		for point: Vector3 in points:
			if point.y > below:
				continue
			var flat: Vector2 = Vector2(point.x, point.z)
			if not found:
				lowest = flat
				highest = flat
				found = true
				continue
			lowest = lowest.min(flat)
			highest = highest.max(flat)

	if not found:
		return Rect2()
	return Rect2(lowest, highest - lowest)


## The cells of a layer that hold a model rather than a blocker — the ones an
## author painted on purpose.
static func hosts(grid: GridMap) -> Array[Vector3i]:
	var found: Array[Vector3i] = []
	var blocker: int = blocker_item(grid)
	for cell: Vector3i in grid.get_used_cells():
		if grid.get_cell_item(cell) != blocker:
			found.append(cell)
	return found


## The id of the invisible item in this layer's palette, or `INVALID_CELL_ITEM`
## when the palette has none — a library built before this existed.
static func blocker_item(grid: GridMap) -> int:
	if grid.mesh_library == null:
		return GridMap.INVALID_CELL_ITEM
	var id: int = grid.mesh_library.find_item_by_name(BLOCKER)
	return id if id >= 0 else GridMap.INVALID_CELL_ITEM


## Fills in one model's footprint, and answers how many cells it took.
##
## Only ever writes to a cell that is empty. A cell already holding something is
## one an author put there, and the two possible mistakes are not equal: a tile
## overwritten is work lost, and a cell left unblocked is a wall you can walk
## through — which the next playtest finds.
static func fill(grid: GridMap, cell: Vector3i, below: float = REACH) -> int:
	var blocker: int = blocker_item(grid)
	if blocker == GridMap.INVALID_CELL_ITEM:
		return 0

	var filled: int = 0
	for at: Vector3i in footprint(grid, cell, below):
		if at == cell or grid.get_cell_item(at) != GridMap.INVALID_CELL_ITEM:
			continue
		grid.set_cell_item(at, blocker)
		filled += 1
	return filled


## Takes back the blockers a model was holding up, and answers how many.
##
## A cell covered by something else that is still there is left alone: two houses
## sharing a wall must not unblock it when one of them goes.
static func clear(
	grid: GridMap, cell: Vector3i, below: float = REACH,
	was: int = GridMap.INVALID_CELL_ITEM
) -> int:
	var blocker: int = blocker_item(grid)
	if blocker == GridMap.INVALID_CELL_ITEM:
		return 0

	var held: Dictionary[Vector3i, bool] = {}
	for other: Vector3i in hosts(grid):
		if other == cell:
			continue
		for at: Vector3i in footprint(grid, other, below):
			held[at] = true

	var taken: int = 0
	for at: Vector3i in footprint(grid, cell, below, was):
		if at == cell or held.has(at) or grid.get_cell_item(at) != blocker:
			continue
		grid.set_cell_item(at, GridMap.INVALID_CELL_ITEM)
		taken += 1
	return taken
