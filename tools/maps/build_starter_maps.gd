extends SceneTree

## Builds the starter maps and the tile library they use.
##
##   godot --headless --path . --script tools/maps/build_starter_maps.gd
##
## Generated rather than painted, and that is the exception rather than the rule.
## Spec 14 says a map is painted in the editor, because a tile grid's meaning is
## visual and nobody catches a level-design mistake by reading coordinates. These
## two exist so there is *something* to walk on before anybody paints, and they
## are ordinary scenes — open one in the editor and paint over it.
##
## The output is committed, and re-running this overwrites whatever was painted.
## It is a starting point, not a build step.

const TILES: String = "res://game/maps/tiles.meshlib"
const FIELD: String = "res://game/maps/starter_field.tscn"
const CAVE: String = "res://game/maps/starter_cave.tscn"

const GROUND: int = 0
const WALL: int = 1


func _init() -> void:
	DirAccess.make_dir_recursive_absolute("res://game/maps")

	_write_tiles()
	_write_field()
	_write_cave()

	print("starter maps: %s, %s" % [FIELD, CAVE])
	quit()


## Two items: what you stand on and what stops you. Plain boxes — nothing here is
## art, and they exist at all because a GridMap will not hold a cell without a
## mesh library.
func _write_tiles() -> void:
	var library: MeshLibrary = MeshLibrary.new()

	var ground: BoxMesh = BoxMesh.new()
	ground.size = Vector3(2, 0.2, 2)
	library.create_item(GROUND)
	library.set_item_name(GROUND, "ground")
	library.set_item_mesh(GROUND, ground)

	var wall: BoxMesh = BoxMesh.new()
	wall.size = Vector3(2, 2, 2)
	library.create_item(WALL)
	library.set_item_name(WALL, "wall")
	library.set_item_mesh(WALL, wall)

	ResourceSaver.save(library, TILES)


## Eight by six, a wall down the middle, a patch of grass, a sign to read and a
## door east.
func _write_field() -> void:
	# The sign's own cell is blocked: a sign is something you face, not something
	# you stand on. It also puts spec 14's rule on a real map — interacting
	# ignores walkability, or every NPC would be unreachable.
	var walls: Array[Vector2i] = [
		Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(2, 2),
	]
	var map: VltWorldMap = _map("starter_field", Vector2i(8, 6), walls)

	var zone: VltEncounterZone = VltEncounterZone.new()
	zone.name = "Meadow"
	zone.table_id = "placeholder_meadow"
	zone.origin = Vector2i(0, 4)
	zone.size = Vector2i(3, 2)
	_own(map, map, zone)

	var door: VltWarp = VltWarp.new()
	door.name = "DoorEast"
	door.cell = Vector2i(7, 3)
	door.to_map = "starter_cave"
	door.to_cell = Vector2i(1, 2)
	door.to_facing = VltFacing.Direction.EAST
	_own(map, map, door)

	_sign(map, "Sign", Vector2i(2, 2), "sign_field")
	_save(map, FIELD)


## A small room with the way back, and something that answers differently once
## the sign has been read — the smallest thing that proves a flag crosses a map.
func _write_cave() -> void:
	var map: VltWorldMap = _map("starter_cave", Vector2i(4, 4), [] as Array[Vector2i])

	var back: VltWarp = VltWarp.new()
	back.name = "DoorWest"
	back.cell = Vector2i(0, 2)
	back.to_map = "starter_field"
	back.to_cell = Vector2i(6, 3)
	back.to_facing = VltFacing.Direction.WEST
	_own(map, map, back)

	var event: VltEvent = VltEvent.new()
	event.name = "Echo"
	event.trigger = VltEvent.Trigger.INTERACT
	event.cell = Vector2i(2, 1)
	_own(map, map, event)

	var branch: VltBranchStep = VltBranchStep.new()
	branch.name = "IfRead"
	branch.flag = "read_the_sign"
	_own(map, event, branch)

	var known: VltSayStep = VltSayStep.new()
	known.name = "Known"
	known.line_id = "sign_echo_known"
	_own(map, branch, known)

	var unknown: VltSayStep = VltSayStep.new()
	unknown.name = "Unknown"
	unknown.line_id = "sign_echo_unknown"
	_own(map, branch, unknown)

	branch.when_set = known
	branch.otherwise = unknown

	_save(map, CAVE)


## A sign that says a line and remembers it was read. The flag is what the cave
## reads, which is the whole point of having two maps at all.
func _sign(map: VltWorldMap, node_name: String, at: Vector2i, line: String) -> void:
	var event: VltEvent = VltEvent.new()
	event.name = node_name
	event.trigger = VltEvent.Trigger.INTERACT
	event.cell = at
	_own(map, map, event)

	var say: VltSayStep = VltSayStep.new()
	say.name = "Say"
	say.line_id = line
	_own(map, event, say)

	var flag: VltSetFlagStep = VltSetFlagStep.new()
	flag.name = "Remember"
	flag.flag = "read_the_sign"
	flag.value = true
	_own(map, event, flag)


func _map(id: String, size: Vector2i, walls: Array[Vector2i]) -> VltWorldMap:
	var map: VltWorldMap = VltWorldMap.new()
	map.name = id
	map.map_id = id

	map.terrain = _grid("Terrain", _filled(size), GROUND)
	map.blocking = _grid("Blocking", walls, WALL)
	_own(map, map, map.terrain)
	_own(map, map, map.blocking)
	return map


func _grid(node_name: String, cells: Array[Vector2i], item: int) -> GridMap:
	var grid: GridMap = GridMap.new()
	grid.name = node_name
	grid.mesh_library = load(TILES)
	for at: Vector2i in cells:
		grid.set_cell_item(Vector3i(at.x, VltWorldMap.GROUND, at.y), item)
	return grid


func _filled(size: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x: int in range(size.x):
		for z: int in range(size.y):
			cells.append(Vector2i(x, z))
	return cells


## Godot packs only nodes whose owner is the scene root. Forgetting that is the
## single trap in generating a scene rather than painting one: the result saves
## without error and comes back holding nothing.
func _own(root: Node, parent: Node, child: Node) -> void:
	parent.add_child(child)
	child.owner = root


func _save(map: VltWorldMap, path: String) -> void:
	var packed: PackedScene = PackedScene.new()
	packed.pack(map)
	ResourceSaver.save(packed, path)
	map.free()
