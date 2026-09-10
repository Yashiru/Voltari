@tool
class_name VltNewMap
extends RefCounted

## A map to start from.
##
## Building one by hand is a scene, a `VltWorldMap`, three `GridMap`s and three
## exports wired in the inspector — five minutes of assembly that is the same
## five minutes every time and wrong in one place when it goes wrong.
##
## What it does **not** do is fill anything in for you beyond a rectangle of
## ground. A new map has no warps, no zones, no events and no rest point, so the
## validator will say it cannot recover a defeat. That is true, and it is the
## first thing to fix rather than something to hide.

## `snake_case`, starting with a letter. A map id is held in a save
## (decision 0040), so it is an identifier and not a title.
const IDENTIFIER: String = "^[a-z][a-z0-9_]*$"

## What a map cannot be smaller than. Zero cells is not a map, and a negative
## size silently produces one too.
const SMALLEST: int = 1

## How wide a cell is, in metres, and how big its art is drawn.
##
## **Two numbers because they answer two questions.** `CELL_SIZE` is how far apart
## cells are; `ART_SCALE` is how large the mesh in one is drawn. The tile library
## is authored at two metres a tile, so on a one-metre grid it is drawn at half —
## and a tile then fills its cell exactly instead of overlapping its neighbours
## four times over.
##
## One metre is a cell a person fits in. At two, a 1.7 m character stood on a
## tile nearly wider than they are tall, and everything read as furniture built
## for somebody else.
##
## Both live here because this is where a map is shaped. Changing them changes
## new maps; an existing map carries its own, which is what makes the change
## reversible one map at a time.
const CELL_SIZE: float = 1.0
const ART_SCALE: float = 0.5


class Result:
	extends RefCounted

	var path: String = ""
	var problems: PackedStringArray = PackedStringArray()

	## Which library item filled the terrain, for the report to name.
	var ground: String = ""

	func worked() -> bool:
		return problems.is_empty()


## Writes a new map and says where it went.
##
## `ground` names an item in the library; empty takes the first one there is. A
## map whose terrain is empty exists nowhere — every cell would be off the map —
## so the rectangle is filled rather than left to be painted.
static func create(
	map_id: String, size: Vector2i, library_path: String, ground: String, folder: String
) -> Result:
	var result: Result = Result.new()
	result.path = "%s/%s.tscn" % [folder, map_id]

	var refusal: String = _refuse(map_id, size, result.path)
	if refusal != "":
		result.problems.append(refusal)
		return result

	var library: MeshLibrary = null
	if not library_path.is_empty():
		library = ResourceLoader.load(library_path, "MeshLibrary") as MeshLibrary
		if library == null:
			result.problems.append("no tile library at %s" % library_path)
			return result

	var item: int = _ground_item(library, ground)
	if library != null and item == GridMap.INVALID_CELL_ITEM:
		result.problems.append("the tile library has no item named \"%s\"" % ground)
		return result

	var map: VltWorldMap = _build(map_id, size, library, item)
	if library != null:
		result.ground = library.get_item_name(item)

	var packed: PackedScene = PackedScene.new()
	var packing: Error = packed.pack(map)
	map.free()

	if packing != OK:
		result.problems.append("could not pack the map (error %d)" % packing)
		return result

	var saved: Error = ResourceSaver.save(packed, result.path)
	if saved != OK:
		result.problems.append("could not write %s (error %d)" % [result.path, saved])

	return result


## Empty when the request is acceptable, otherwise why not.
##
## Overwriting is the one refusal that matters. Everything else here is a typo
## caught early; writing over a painted map destroys work that has no other copy.
static func _refuse(map_id: String, size: Vector2i, path: String) -> String:
	var pattern: RegEx = RegEx.new()
	pattern.compile(IDENTIFIER)

	if pattern.search(map_id) == null:
		return "\"%s\" is not a map id — lower case, digits and underscores, starting with a letter" % map_id
	if size.x < SMALLEST or size.y < SMALLEST:
		return "a map is at least %d by %d cells" % [SMALLEST, SMALLEST]
	if ResourceLoader.exists(path) or FileAccess.file_exists(path):
		return "%s already exists, and overwriting a painted map is not something to do by accident" % path

	return ""


static func _ground_item(library: MeshLibrary, ground: String) -> int:
	if library == null:
		return GridMap.INVALID_CELL_ITEM

	var ids: PackedInt32Array = library.get_item_list()
	if ids.is_empty():
		return GridMap.INVALID_CELL_ITEM

	if ground.is_empty():
		return ids[0]

	for id: int in ids:
		if library.get_item_name(id) == ground:
			return id
	return GridMap.INVALID_CELL_ITEM


static func _build(
	map_id: String, size: Vector2i, library: MeshLibrary, item: int
) -> VltWorldMap:
	var map: VltWorldMap = VltWorldMap.new()
	map.name = map_id
	map.map_id = map_id

	map.terrain = _layer("Terrain", library)
	map.blocking = _layer("Blocking", library)
	map.decor = _layer("Decor", library)

	if item != GridMap.INVALID_CELL_ITEM:
		for x: int in range(size.x):
			for z: int in range(size.y):
				map.terrain.set_cell_item(Vector3i(x, VltWorldMap.GROUND, z), item)

	# Godot packs only nodes whose owner is the scene root. It is the one trap in
	# generating a scene rather than painting one — the file saves without error
	# and comes back holding nothing — and `tools/maps/build_starter_maps.gd`
	# meets it too.
	for layer: GridMap in [map.terrain, map.blocking, map.decor]:
		map.add_child(layer)
		layer.owner = map

	return map


## All three layers share the palette. Blocking and decoration start empty, and
## a layer with no library cannot be painted into at all — which would make two
## thirds of a new map unusable until somebody noticed why.
static func _layer(layer_name: String, library: MeshLibrary) -> GridMap:
	var layer: GridMap = GridMap.new()
	layer.name = layer_name
	layer.mesh_library = library
	layer.cell_size = Vector3.ONE * CELL_SIZE
	layer.cell_scale = ART_SCALE
	return layer
