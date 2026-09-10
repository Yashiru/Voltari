extends SceneTree

## Renders the grass so it can be looked at.
##
##   godot --path . --script tools/grass/preview.gd -- <folder> [item]
##
## A shader is the one thing in this repository that cannot be judged by a test.
## Everything else is asserted; this is looked at. It lays a patch of real grass
## on a real grid, walks somebody through it, and writes a contact sheet — so a
## change can be compared against the frame before it rather than against a
## memory of it.
##
## Four things come out, and each answers a different question:
##
##   still.png     the field with nobody in it — is the wind alive, and is the
##                 field varied, or does it breathe as one animal?
##   walk_NN.png   the walk, from the angle the game looks at the world
##   top_off.png   the same instant from above, with the walker ignored
##   top_on.png    the same instant from above, with the walker felt
##
## The last two are a pair on purpose: a footprint is obvious in the difference
## between them and easy to imagine into either one alone.
##
## It reads the quarantined library (decision 0027) and runs on one machine only,
## which is the same footing as the manifest builder.

const LIBRARY: String = "res://game/assets/placeholders/brawl_arena.meshlib"
const ITEM: String = "GrassB"
const OUT: String = "user://grass"

## A patch on the grid new maps use, scattered rather than solid: a field with no
## gaps in it is a carpet, and a carpet hides everything this is for.
const PATCH: int = 26
const CELL: float = 0.5
const ART: float = 0.25
const DENSITY: float = 0.62
const SCATTER_SEED: int = 20260910

## Long enough for the wake to have something to trail behind.
const STRIDE: float = 0.24
const STEPS: int = 16
const HOLD: int = 8
const TICK: float = 1.0 / 60.0
const TICKS_PER_FRAME: int = 6

var _grass: GrassField = GrassField.new()
var _grid: GridMap
var _camera: Camera3D
var _marker: MeshInstance3D
var _item_name: String = ITEM


func _init() -> void:
	var folder: String = _argument(0, ProjectSettings.globalize_path(OUT))
	_item_name = _argument(1, ITEM)
	DirAccess.make_dir_recursive_absolute(folder)

	if not _build():
		quit()
		return

	# Anything after the item is `name=value`, applied to every grass material.
	# Tuning a shader means comparing two renders that differ in one number, and
	# editing the file between them makes that two changes rather than one.
	_override(2)

	# Nobody in it. Everything visible here is wind and variation.
	_marker.visible = false
	_grass.set_strength(0.0)
	await _settle(8)
	_save("%s/still.png" % folder)

	# The walk, from the game's own angle.
	_marker.visible = true
	_grass.set_strength(1.0)
	var path: Array[Vector3] = _path()
	_grass.place(path[0])

	for index: int in range(path.size()):
		for tick: int in range(TICKS_PER_FRAME):
			_grass.follow(path[index], TICK)
			_marker.position = path[index] + Vector3(0.0, 0.45, 0.0)
			await process_frame
		await RenderingServer.frame_post_draw
		_save("%s/walk_%02d.png" % [folder, index])

	# The wake, from above and while moving. It is the one thing that cannot be
	# seen from a standing still frame: what is behind somebody is only behind
	# them while they are going somewhere.
	_look_down()
	_grass.place(path[0])
	for index: int in range(path.size()):
		for tick: int in range(TICKS_PER_FRAME):
			_grass.follow(path[index], TICK)
			_marker.position = path[index] + Vector3(0.0, 0.45, 0.0)
			await process_frame
		await RenderingServer.frame_post_draw
		if index % 3 == 0:
			_save("%s/wake_%02d.png" % [folder, index])

	# The pair. Same instant, same wind, one with the walker felt and one
	# without — so the footprint is a difference rather than an impression.
	#
	# The walker is put under the middle of the frame first. Judging a footprint
	# that sits off to one side means judging mostly the pixels it cannot reach.
	_grass.place(Vector3.ZERO)
	_marker.position = Vector3(0.0, 0.45, 0.0)
	_look_down()
	_grass.set_strength(0.0)
	await _settle(4)
	_save("%s/top_off.png" % folder)

	_grass.set_strength(1.0)
	await _settle(4)
	_save("%s/top_on.png" % folder)

	print("wrote the sheet to %s" % folder)
	quit()


func _path() -> Array[Vector3]:
	var walk: Array[Vector3] = []
	for step: int in range(STEPS):
		walk.append(Vector3(-1.9 + float(step) * STRIDE, 0.0, 0.0))
	for hold: int in range(HOLD):
		walk.append(walk[walk.size() - 1])
	return walk


## Applies `name=value` arguments to the materials, so a render can be asked for
## with one number changed.
func _override(from: int) -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	for index: int in range(from, arguments.size()):
		var pair: PackedStringArray = arguments[index].split("=")
		if pair.size() != 2:
			continue
		_grass.tune(pair[0], float(pair[1]))
		print("  %s = %s" % [pair[0], pair[1]])


func _argument(at: int, fallback: String) -> String:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	return arguments[at] if arguments.size() > at else fallback


func _build() -> bool:
	var library: MeshLibrary = ResourceLoader.load(
		LIBRARY, "MeshLibrary", ResourceLoader.CACHE_MODE_IGNORE
	) as MeshLibrary
	if library == null:
		print("no tile library at ", LIBRARY)
		return false

	var item: int = -1
	for id: int in library.get_item_list():
		if library.get_item_name(id) == _item_name:
			item = id
	if item < 0:
		print("no item named ", _item_name)
		return false

	_sky()
	_ground()

	_grid = GridMap.new()
	_grid.cell_size = Vector3.ONE * CELL
	_grid.cell_scale = ART
	_grid.mesh_library = library

	var scatter: RandomNumberGenerator = RandomNumberGenerator.new()
	scatter.seed = SCATTER_SEED
	for x: int in range(PATCH):
		for z: int in range(PATCH):
			if scatter.randf() <= DENSITY:
				_grid.set_cell_item(Vector3i(x, 0, z), item)
	root.add_child(_grid)
	_grid.position = Vector3(-float(PATCH) * CELL * 0.5, 0.0, -float(PATCH) * CELL * 0.5)

	_camera = Camera3D.new()
	root.add_child(_camera)
	_look_across()
	_camera.make_current()

	# Somewhere to look. Without it there is no telling whether the grass opens
	# around the walker or around nothing.
	_marker = MeshInstance3D.new()
	var pill: CapsuleMesh = CapsuleMesh.new()
	pill.radius = 0.16
	pill.height = 0.9
	_marker.mesh = pill
	var paint: StandardMaterial3D = StandardMaterial3D.new()
	paint.albedo_color = Color(0.92, 0.3, 0.26)
	_marker.material_override = paint
	root.add_child(_marker)

	_grass.of_layers([_grid] as Array[GridMap])
	print("materials found: %d, item %s" % [_grass.material_count(), _item_name])
	return true


## The angle the game looks at the world from, and the only one worth judging.
func _look_across() -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.look_at_from_position(
		Vector3(0.9, 1.5, 2.8), Vector3(0.0, 0.22, -0.3), Vector3.UP
	)


func _look_down() -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.look_at_from_position(
		Vector3(0.0, 3.0, 0.7), Vector3.ZERO, Vector3.FORWARD
	)


func _sky() -> void:
	var world: WorldEnvironment = WorldEnvironment.new()
	var environment: Environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.56, 0.70, 0.80)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.60, 0.70, 0.80)
	environment.ambient_light_energy = 0.55
	world.environment = environment
	root.add_child(world)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, -34, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	root.add_child(sun)


## Something for the grass to stand in. Without it the field floats over the sky
## and nothing can be said about how it sits in the ground.
func _ground() -> void:
	var floor_mesh: MeshInstance3D = MeshInstance3D.new()
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	var soil: StandardMaterial3D = StandardMaterial3D.new()
	soil.albedo_color = Color(0.22, 0.30, 0.16)
	soil.roughness = 1.0
	floor_mesh.material_override = soil
	root.add_child(floor_mesh)


func _settle(frames: int) -> void:
	for frame: int in range(frames):
		await process_frame
	await RenderingServer.frame_post_draw


func _save(path: String) -> void:
	root.get_texture().get_image().save_png(path)
