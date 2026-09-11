@tool
class_name TurfPatch
extends GPUParticles3D

## Short grass on the cells somebody chose, with the settings they chose at the
## time.
##
## **Turf is not grass**, in this project's vocabulary. The tall tufts are map
## items with their own model and their own shader (`grass_parting.gdshader`).
## This is the few centimetres of lawn on the ground underneath, and the two are
## meant to be seen together: tufts standing in turf.
##
## The same shape as `VltFoliagePatch`, deliberately. Nothing in this game grows
## turf unless one of these says so: no automatic pass, no name to match, no
## default. One press of *Sow grass* is one patch carrying its own settings, so
## two areas can be sown differently and either tuned or deleted without touching
## the other.
##
## **It stores cells and numbers, never geometry.** A handful of floats and a list
## of cells go into the `.tscn`; where each blade stands is worked out on the GPU
## from its own index every frame, so a patch costs the scene a few hundred bytes
## whatever its size.
##
## Foliage and turf place their scatter differently on purpose. A leaf lands on
## the *surface of a model*, which needs the mesh and is therefore baked once. A
## blade of turf stands on the *ground plane of a cell*, which needs nothing but
## the cell — so it can be a particle, and a particle costs no memory and no bake.

## Where the pieces live. Named rather than preloaded so a missing shader is a
## warning on one patch and not a scene that refuses to open.
const SCATTER_SHADER: String = "res://game/presentation/world/turf_scatter.gdshader"
const BLADE_SHADER: String = "res://game/presentation/world/turf.gdshader"

## The lawn's colour when nobody has picked one.
##
## Its own, not the ground's underneath: grass is green whether it comes up
## through soil, sand or stone, and inheriting the surface's colour would give a
## desert a sand-coloured lawn — a bug that looks like a decision.
const GREEN: Color = Color(0.11, 0.42, 0.05)

## And at the tip. Lighter and yellower, which is what a blade catching the sky
## does and what stops a field reading as one flat green sheet.
const TIP: Color = Color(0.42, 0.71, 0.13)

## A ceiling on blades in one patch, whatever the density and the cell count ask
## for.
##
## **Not a limit on density** — the density field has none. This is the last stop
## before a typo takes the editor down: two hundred cells at a hundred thousand a
## metre would ask for two billion instances and there would be nothing left to
## press undo with. A patch held here says so in the output rather than quietly
## drawing less than it was asked for.
const MOST_BLADES: int = 4000000

## How far past the cells the blades may reach, for the visibility box. Generous:
## a box that is too tight makes the lawn blink out at the edge of the screen,
## which is far worse than one slightly too large.
const HEADROOM: float = 0.5

## Everything this node writes for itself, and must therefore never be saved.
##
## A `@tool` script that sets a property in the editor has it serialised into the
## `.tscn` — and **a stored value outlives the code that set it**, so the scene
## would quietly keep the materials of whatever this file looked like the day it
## was last opened. That trap has already cost this project an afternoon once, on
## a `MeshLibrary`. Taking the storage flag off them is what makes the promise
## above — cells and numbers, never geometry — actually true.
##
## An `Array[String]`: the packed form is a call, and a call is not a constant
## expression in GDScript.
const BUILT: Array[String] = [
	"amount", "process_material", "draw_pass_1", "material_override",
	"visibility_aabb", "lifetime", "explosiveness", "fixed_fps", "local_coords",
	"cast_shadow", "emitting",
]

## The layer whose cells these are. Set by the plugin once the patch is in the
## tree, because the path is resolved against it.
@export var layer: NodePath:
	set(value):
		layer = value
		_rebuild()

## Which cells. Grid coordinates, the same ones the `GridMap` editor selects.
@export var cells: Array[Vector3i] = []:
	set(value):
		cells = value
		_rebuild()

@export_group("lawn")

## Blades a square metre.
##
## The slider stops at two thousand and the field does not: `or_greater` means a
## number can be typed straight in. The dial this feature lives or dies on — a
## blade is five triangles, and `tools/budget/tiers.json` allows 150,000 for a
## whole frame on the low tier — but where that line falls is the author's to
## find, not this file's to impose.
@export_range(10.0, 2000.0, 1.0, "or_greater") var density: float = 300.0:
	set(value):
		density = maxf(value, 1.0)
		_rebuild()

## How tall the tallest blade is, in metres. Five to ten centimetres is what this
## is for.
@export_range(0.01, 0.4, 0.005) var blade_height: float = 0.09:
	set(value):
		blade_height = maxf(value, 0.01)
		_rebuild()

## How much shorter the shortest blades are, as a share of the tallest. At zero
## the lawn has one height, which reads as a mown carpet.
@export_range(0.0, 1.0, 0.01) var height_spread: float = 0.45:
	set(value):
		height_spread = clampf(value, 0.0, 1.0)
		_rebuild()

## How wide a blade is at its root, as a share of its own height. Proportional
## rather than absolute, so a short blade is not a wide stub.
@export_range(0.02, 1.0, 0.01) var blade_width: float = 0.30:
	set(value):
		blade_width = clampf(value, 0.02, 1.0)
		_rebuild()

## How far a blade may wander off its own spot, as a share of the gap between
## spots. At zero the grid shows as rows the moment the camera looks along one.
@export_range(0.0, 1.0, 0.01) var scatter: float = 0.85:
	set(value):
		scatter = clampf(value, 0.0, 1.0)
		_rebuild()

## How far the wind lays a blade over, on top of what the shared wind already
## says. Turf is shorter and stiffer than a tuft, so it takes less of one gust.
@export_range(0.0, 2.0, 0.01) var wind_give: float = 0.55:
	set(value):
		wind_give = clampf(value, 0.0, 2.0)
		_rebuild()

## A nudge up or down from the top of whatever is in the cell, in metres.
##
## Zero is right almost always: the blades are placed on the **top of the model
## actually drawn in each cell**, read from its own mesh, so a raised tile grows
## grass on its raised surface and a sunken one on its sunken surface without
## anybody being told. This is for the model whose top face is not where its
## bounding box says it is.
@export_range(-1.0, 1.0, 0.005) var lift: float = 0.0:
	set(value):
		lift = value
		_rebuild()

## How far a blade bows over, as a share of its own height.
##
## A straight blade is a spike, and a field of spikes reads as a pin cushion. The
## bow is what turns it into grass, and it is geometry rather than wind: it is
## there when the air is still.
@export_range(0.0, 1.2, 0.01) var blade_bend: float = 0.45:
	set(value):
		blade_bend = clampf(value, 0.0, 1.2)
		_rebuild()

@export_group("colour")

## The colour at the root, and the colour at the tip.
##
## Two and not one because a blade lit from above is lighter where it catches the
## sky, and one flat green over a whole field is the single thing that most makes
## grass read as carpet. The gradient runs on the blade, not on the field, so it
## survives a camera that moves.
@export var colour: Color = GREEN:
	set(value):
		colour = value
		_rebuild()

@export var tip_colour: Color = TIP:
	set(value):
		tip_colour = value
		_rebuild()

## The cells that actually hold something, which is what is sown. Kept so the
## spots texture and the box are built from the same list the count came from.
var _filled: Array[Vector3i] = []

var _scatter: ShaderMaterial = null
var _blade: ShaderMaterial = null


func _ready() -> void:
	_rebuild()


func _validate_property(property: Dictionary) -> void:
	var name: String = property["name"]
	if not BUILT.has(name):
		return
	var usage: int = property["usage"]
	property["usage"] = usage & ~PROPERTY_USAGE_STORAGE


## How many blades this patch is drawing. For the plugin, which says so when it
## sows, and for anything counting against a budget.
func blade_total() -> int:
	return amount


## How many blades stand in one cell, from the density and the grid's own cell
## footprint. Asked of the grid rather than assumed: both are settings somebody
## can change.
func blades_per_cell() -> int:
	var grid: GridMap = get_node_or_null(layer) as GridMap
	if grid == null:
		return 0
	var footprint: float = absf(grid.cell_size.x) * absf(grid.cell_size.z)
	return maxi(roundi(density * footprint), 1)


func _rebuild() -> void:
	if not is_inside_tree():
		return

	var grid: GridMap = get_node_or_null(layer) as GridMap
	if grid == null or cells.is_empty():
		amount = 1
		emitting = false
		return

	var scatter_shader: Shader = ResourceLoader.load(SCATTER_SHADER, "Shader") as Shader
	var blade_shader: Shader = ResourceLoader.load(BLADE_SHADER, "Shader") as Shader
	if scatter_shader == null or blade_shader == null:
		push_warning("no turf shaders — this patch stays bare")
		return

	# The cells are the grid's, so the patch is put where the grid is and
	# everything below is measured in the grid's own space. The same thing
	# `VltFoliagePatch` does, for the same reason.
	global_transform = grid.global_transform

	# A cell holding no item has no surface to stand on, so it grows nothing. The
	# author selected a rectangle; the ground inside it may have holes.
	var filled: Array[Vector3i] = []
	for cell: Vector3i in cells:
		if grid.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM:
			filled.append(cell)
	if filled.is_empty():
		amount = 1
		emitting = false
		return
	_filled = filled

	var per_cell: int = blades_per_cell()
	var wanted: int = clampi(filled.size() * per_cell, 1, MOST_BLADES)
	# Said rather than done silently: a patch held under the guard draws fewer
	# blades a metre than its density claims, and saying nothing would make the
	# density field lie.
	if filled.size() * per_cell > MOST_BLADES:
		per_cell = maxi(wanted / filled.size(), 1)
		push_warning("turf held at %d blades — fewer a metre than asked" % MOST_BLADES)

	if _scatter == null:
		_scatter = ShaderMaterial.new()
	_scatter.shader = scatter_shader
	_scatter.set_shader_parameter("cell_spots", _spots(grid))
	_scatter.set_shader_parameter("cell_count", float(filled.size()))
	_scatter.set_shader_parameter("per_cell", float(per_cell))
	_scatter.set_shader_parameter("cell_width", absf(grid.cell_size.x))
	_scatter.set_shader_parameter("cell_depth", absf(grid.cell_size.z))
	_scatter.set_shader_parameter("blade_height", blade_height)
	_scatter.set_shader_parameter("blade_width", blade_width)
	_scatter.set_shader_parameter("height_spread", height_spread)
	_scatter.set_shader_parameter("blade_scatter", scatter)
	_scatter.set_shader_parameter("blade_give", wind_give)

	if _blade == null:
		_blade = ShaderMaterial.new()
	_blade.shader = blade_shader
	# The same look everything else in the world wears, from the same file the
	# creatures and the tiles read. A lawn on the shader's bare defaults would be
	# a patch of plain `comic` in a comic-manga world.
	var look: Dictionary[String, Variant] = CreatureView.preset_values(
		CreatureView.roster_style()
	)
	for name: String in look:
		_blade.set_shader_parameter(name, look[name])
	# After the look: the world is not a subject, and no preset names either.
	_blade.set_shader_parameter("key_follows_camera", 0.0)
	_blade.set_shader_parameter("shape_round", 0.0)
	_blade.set_shader_parameter("albedo", colour)
	_blade.set_shader_parameter("tip_tint", tip_colour)
	# Full, because the two exported colours *are* the gradient. A partial mix
	# would mean the tip colour the author picked is not the colour they get.
	_blade.set_shader_parameter("tip_tint_amount", 1.0)
	_scatter.set_shader_parameter("blade_bend", blade_bend)

	amount = wanted
	process_material = _scatter
	draw_pass_1 = _blade_mesh()
	material_override = _blade

	# A blade is placed by its index, not carried by a lifetime, so none of the
	# usual particle timing means anything. What matters is only that all of them
	# are alive at once.
	lifetime = 1.0
	explosiveness = 1.0
	fixed_fps = 0
	# World space, not patch space. The wind is a world question — a gust has to
	# cross from one patch to the next without restarting — and that is only true
	# if a blade knows where it really stands.
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = _box(grid)
	emitting = true


## Every sown cell's own origin, as a texture the scatter reads by index.
##
## A texture and not an array uniform because a patch may carry hundreds of cells
## and an array has a ceiling written into the shader. One texel per cell,
## unfiltered, so what is read back is what was written.
func _spots(grid: GridMap) -> ImageTexture:
	var spots: Image = Image.create(maxi(_filled.size(), 1), 1, false, Image.FORMAT_RGBF)
	for index: int in range(_filled.size()):
		var at: Vector3 = grid.map_to_local(_filled[index])
		spots.set_pixel(index, 0, Color(at.x, _surface_of(grid, _filled[index]), at.z))
	return ImageTexture.create_from_image(spots)


## The height of the top of whatever is drawn in a cell, in the grid's space.
##
## **This is what makes grass land on the ground rather than inside it.** A cell's
## own origin is its centre, not its surface, and the model in it is drawn at the
## grid's `cell_scale` — so the top is the model's own bounding box, scaled, above
## the cell origin. Read per cell rather than once, because a patch can cover a
## flat tile and a raised block and each wants its own surface.
##
## A cell holding nothing falls back to its origin. Those cells are skipped before
## they get here, so this is a floor under a race, not a case.
func _surface_of(grid: GridMap, cell: Vector3i) -> float:
	var origin: float = grid.map_to_local(cell).y + lift
	if grid.mesh_library == null:
		return origin
	var item: int = grid.get_cell_item(cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return origin
	var mesh: Mesh = grid.mesh_library.get_item_mesh(item)
	if mesh == null:
		return origin
	return origin + mesh.get_aabb().end.y * grid.cell_scale


## What the patch occupies, from the cells it was given.
##
## Measured rather than assumed: a patch is whatever shape the author selected,
## and a box around the whole grid would keep a lawn drawn long after it had left
## the screen.
func _box(grid: GridMap) -> AABB:
	var box: AABB = AABB(grid.map_to_local(_filled[0]), Vector3.ZERO)
	for cell: Vector3i in _filled:
		box = box.expand(Vector3(
			grid.map_to_local(cell).x, _surface_of(grid, cell), grid.map_to_local(cell).z
		))
	return box.grow(maxf(absf(grid.cell_size.x), absf(grid.cell_size.z))).grow(HEADROOM)


## One blade: a tapered strip, two segments and a point.
##
## Built here rather than imported, because it is seven vertices and a file would
## be one more thing to keep in step with the shader that reads its `UV.y`.
##
## **Its normals point straight up, not out of its face.** A card shaded by its
## own face normal flips as it turns, and at three hundred blades a square metre
## that reads as flicker. Pointing them up makes a blade shade like the ground it
## grows from, which is what a stylised lawn wants — see `turf.gdshader`.
func _blade_mesh() -> ArrayMesh:
	var points: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var faces: PackedInt32Array = PackedInt32Array()

	# Rungs up the blade, narrowing, then a point. The model is one unit tall and
	# one unit wide: the scatter scales it.
	#
	# Four rungs rather than two, because the bow below needs somewhere to bend.
	# A blade with one joint folds; a blade with three curves.
	var rungs: PackedFloat32Array = PackedFloat32Array([0.0, 0.30, 0.56, 0.79])
	var widths: PackedFloat32Array = PackedFloat32Array([0.5, 0.44, 0.34, 0.21])

	for rung: int in range(rungs.size()):
		var up: float = rungs[rung]
		var half: float = widths[rung]
		# Squared, so the root stays planted and the bow gathers towards the tip.
		var over: float = up * up
		points.append(Vector3(-half, up, over))
		points.append(Vector3(half, up, over))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.0, up))
		uvs.append(Vector2(1.0, up))

	var tip: int = points.size()
	points.append(Vector3(0.0, 1.0, 1.0))
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 1.0))

	for rung: int in range(rungs.size() - 1):
		var low: int = rung * 2
		var high: int = low + 2
		faces.append_array([low, high, low + 1])
		faces.append_array([low + 1, high, high + 1])
	faces.append_array([tip - 2, tip, tip - 1])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = faces

	var blade: ArrayMesh = ArrayMesh.new()
	blade.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return blade
