class_name VltFixtureMap
extends RefCounted

## A map built in code, for the world tests (spec 14, section 10).
##
## Built rather than painted on purpose. A `.tscn` fixture would have to be
## opened to be understood, and a test whose setup is invisible is a test nobody
## can check. Everything here is the same node types a painted map uses, so what
## the tests exercise is the production classes and not a stand-in.
##
## `GridMap` needs a mesh library before it will hold a cell, so there is one
## with a single item in it. Nothing is ever rendered — the suite is headless and
## the cell's *presence* is the only thing the rules read.

const MARKER: int = 0


static func mesh_library() -> MeshLibrary:
	var library: MeshLibrary = MeshLibrary.new()
	library.create_item(MARKER)
	library.set_item_name(MARKER, "marker")
	library.set_item_mesh(MARKER, BoxMesh.new())
	return library


static func grid(cells: Array[Vector2i]) -> GridMap:
	var layer: GridMap = GridMap.new()
	layer.mesh_library = mesh_library()
	for cell: Vector2i in cells:
		layer.set_cell_item(Vector3i(cell.x, VltWorldMap.GROUND, cell.y), MARKER)
	return layer


## A blocking layer that speaks in shapes rather than in whole cells.
##
## **What puts a map in shape mode is `_blocked` being in its palette**, so this
## is the smallest palette that has it: the invisible item, and one model to
## paint. Every other fixture layer lacks it and keeps the older reading, where a
## painted cell is a blocked cell — which is what the maps painted before shapes
## existed still mean.
##
## `size` is in the model's own units, and the grid draws it scaled, so a two by
## two model on a half-scale grid is a metre across.
static func shaped(cells: Array[Vector2i], size: Vector3) -> GridMap:
	var library: MeshLibrary = MeshLibrary.new()
	library.create_item(MARKER)
	library.set_item_name(MARKER, "post")
	library.set_item_mesh(MARKER, block(size))
	library.create_item(MARKER + 1)
	library.set_item_name(MARKER + 1, VltWorldMap.BLOCKER)
	library.set_item_mesh(MARKER + 1, ArrayMesh.new())

	var layer: GridMap = GridMap.new()
	layer.mesh_library = library
	for cell: Vector2i in cells:
		layer.set_cell_item(Vector3i(cell.x, VltWorldMap.GROUND, cell.y), MARKER)
	return layer


## A closed box standing on its own origin, centred on it, the way the tile
## library leaves every model.
##
## Closed, because a floor and a ceiling with no walls between them share no
## corner and would be found as two pieces — geometry no model ever has.
static func block(size: Vector3) -> ArrayMesh:
	var low: Vector3 = Vector3(-size.x * 0.5, 0.0, -size.z * 0.5)
	var high: Vector3 = Vector3(size.x * 0.5, size.y, size.z * 0.5)

	var ring: Array[Vector3] = [
		Vector3(low.x, low.y, low.z), Vector3(high.x, low.y, low.z),
		Vector3(high.x, low.y, high.z), Vector3(low.x, low.y, high.z),
	]
	var top: Array[Vector3] = []
	for corner: Vector3 in ring:
		top.append(Vector3(corner.x, high.y, corner.z))

	var points: PackedVector3Array = PackedVector3Array()
	for face: Array in [ring, top]:
		@warning_ignore("unsafe_cast")
		var corners: Array[Vector3] = face as Array[Vector3]
		points.append_array(PackedVector3Array([
			corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]
		]))
	for index: int in range(4):
		var next: int = (index + 1) % 4
		points.append_array(PackedVector3Array([
			ring[index], ring[next], top[next], ring[index], top[next], top[index],
		]))

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points

	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A rectangle of terrain from (0, 0) to (size - 1), which is what almost every
## test wants under it.
static func filled(size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(size.x):
		for z: int in range(size.y):
			cells.append(Vector2i(x, z))
	return cells


static func map(
	id: String,
	walkable: Array[Vector2i],
	blocked: Array[Vector2i] = [],
	decorated: Array[Vector2i] = []
) -> VltWorldMap:
	var built: VltWorldMap = VltWorldMap.new()
	built.map_id = id

	built.terrain = grid(walkable)
	built.blocking = grid(blocked)
	# Always present, usually empty. A layer that only appears in the tests that
	# are about it would leave every other test proving nothing about a map that
	# has one (decision 0054).
	built.decor = grid(decorated)
	built.add_child(built.terrain)
	built.add_child(built.blocking)
	built.add_child(built.decor)
	return built


static func warp(
	at: Vector2i, to_map: String, to_cell: Vector2i, facing: VltFacing.Direction
) -> VltWarp:
	var built: VltWarp = VltWarp.new()
	built.cell = at
	built.to_map = to_map
	built.to_cell = to_cell
	built.to_facing = facing
	return built


static func rest(at: Vector2i, facing: VltFacing.Direction = VltFacing.Direction.SOUTH) -> VltRestPoint:
	var built: VltRestPoint = VltRestPoint.new()
	built.cell = at
	built.facing = facing
	return built


static func zone(table_id: String, origin: Vector2i, size: Vector2i) -> VltEncounterZone:
	var built: VltEncounterZone = VltEncounterZone.new()
	built.table_id = table_id
	built.origin = origin
	built.size = size
	return built


static func table(id: String, rate: int) -> VltEncounterTable:
	return VltEncounterTable.create(id, rate).holds("species_base", 3, 5, 1)
