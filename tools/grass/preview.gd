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
##   still.png     the field with nobody in it — is the wind subtle, and is the
##                 field varied, or does it breathe as one animal?
##   walk_NN.png   walking cell to cell, from the angle the game looks from
##   jostle_NN.png the same, from above, where a cell swinging is unmistakable
##
## It reads the tile library, which is committed like everything else since
## decision 0074 — so it runs anywhere the repository does, rather than on the one
## machine that had the models.

const LIBRARY: String = "res://game/assets/species/brawl_arena.meshlib"
const ITEM: String = "GrassB"
const OUT: String = "user://grass"

## A patch on the grid new maps use, scattered rather than solid: a field with no
## gaps in it is a carpet, and a carpet hides everything this is for.
## The grid new maps are painted on. **The same numbers, read from the same
## place**: a preview on a different grid previews a world nobody plays.
const PATCH: int = 16
const CELL: float = VltNewMap.CELL_SIZE
const ART: float = VltNewMap.ART_SCALE
const DENSITY: float = 0.62
const SCATTER_SEED: int = 20260910

## A step every third of a second, which is the pace the world walks at, and a
## frame saved often enough to catch a swing settling.
const STEPS: int = 7
const TICK: float = 1.0 / 60.0
const TICKS_PER_STEP: int = 20
const SAVE_EVERY: int = 5

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

	# Walking cell to cell. A step is one call, and the frames between it are the
	# swing settling — which is the whole of what there is to look at.
	_marker.visible = true
	_grass.set_strength(1.0)
	_grass.quiet()
	await _step_through(folder, "walk")

	# The same, from above. A cell swinging is easiest to see looking straight
	# down at the row it is in.
	_look_down()
	_grass.quiet()
	await _step_through(folder, "jostle")

	print("wrote the sheet to %s" % folder)
	quit()


## Walks cell to cell, saving a frame every so often through each step. The
## interesting frames are the ones *between* steps: a swing that is over by the
## next footfall is a swing nobody sees.
func _step_through(folder: String, name: String) -> void:
	var frame: int = 0
	for step: int in range(STEPS):
		var at: Vector3 = Vector3(-3.0 + float(step) * CELL, 0.0, 0.0)
		_grass.enter_cell(at)
		for tick: int in range(TICKS_PER_STEP):
			_grass.advance(TICK)
			_marker.position = at + Vector3(0.0, 0.45, 0.0)
			await process_frame
			if tick % SAVE_EVERY == 0:
				await RenderingServer.frame_post_draw
				_save("%s/%s_%02d.png" % [folder, name, frame])
				frame += 1


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
	_grass.set_cell_size(CELL)
	print("materials found: %d, item %s" % [_grass.material_count(), _item_name])
	return true


## The angle the game looks at the world from, and the only one worth judging.
func _look_across() -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.look_at_from_position(
		Vector3(1.4, 2.2, 4.0), Vector3(0.0, 0.35, -0.4), Vector3.UP
	)


func _look_down() -> void:
	_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	_camera.look_at_from_position(
		Vector3(0.0, 5.0, 1.2), Vector3.ZERO, Vector3.FORWARD
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
