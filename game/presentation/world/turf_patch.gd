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
const MAT_SHADER: String = "res://game/presentation/world/turf_mat.gdshader"

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

## How far above the grass the slice still looks, in metres.
##
## A rim, a frame, a low wall: things that stand a little proud of the lawn and
## that grass must not grow through, even though no blade reaches them. Kept
## short — a palm's canopy is twelve metres up and must never be counted, or the
## clearance becomes the shadow of the tree.
const SLICE_ABOVE: float = 0.6

## How far below the ground the slice still looks, in metres.
##
## A rim flush with the grass, or a tile whose top face sits a hair under it,
## must still count. Small: any deeper and a pit's inside walls start being
## measured as if they were on the surface.
const SLICE_BELOW: float = 0.06

## Texels a metre in the room field, and the most a side may have.
##
## Sixteen is a little over six centimetres, which is finer than any clearance
## anybody would set and far finer than a blade is wide. The cap is the usual
## guard against a patch sized by accident.
const FIELD_DETAIL: float = 8.0
const FIELD_MOST: int = 1024

## How far above the surface the mat is laid, in metres.
##
## Just enough to win the depth test against the model it covers. Larger and it
## floats on a slope; smaller and the two fight and flicker.
const MAT_LIFT: float = 0.004

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

## Whether the patch grows itself again when the map under it is edited.
##
## A patch is worked out once, from the map as it stood when it was sown. Paint a
## well in the middle of a lawn afterwards and the grass keeps growing through it,
## because nothing tells the patch anything happened.
##
## With this on, the editor plugin notices and resows it a moment after the last
## change — see `map_signature`. Off, the patch stays exactly as it was sown until
## something asks it to change, which is what a patch large enough for the rebuild
## to be felt will want.
##
## **Editor only.** In a running game nothing repaints a `GridMap`, so nobody is
## watching and this costs nothing.
@export var follow_map: bool = true

@export_group("lawn")

## Blades a square metre.
##
## The slider stops at two thousand and the field does not: `or_greater` means a
## number can be typed straight in. The dial this feature lives or dies on — a
## blade is five triangles, and `tools/budget/tiers.json` allows 150,000 for a
## whole frame on the low tier — but where that line falls is the author's to
## find, not this file's to impose.
@export_range(10.0, 2000.0, 1.0, "or_greater") var density: float = 650.0:
	set(value):
		density = maxf(value, 1.0)
		_rebuild()

## How tall the tallest blade is, in metres.
##
## The default is what the maintainer settled on by looking at it. Shells were
## rejected for this feature at five to ten centimetres and instancing wins by a
## wider margin the taller it gets, so nothing here breaks as it rises — but the
## triangle count is proportional to the density, not to the height, and the
## silhouette is what starts costing at a grazing camera.
@export_range(0.01, 0.4, 0.005) var blade_height: float = 0.2:
	set(value):
		blade_height = maxf(value, 0.01)
		_rebuild()

## How much shorter the shortest blades are, as a share of the tallest. At zero
## the lawn has one height, which reads as a mown carpet.
@export_range(0.0, 1.0, 0.01) var height_spread: float = 0.25:
	set(value):
		height_spread = clampf(value, 0.0, 1.0)
		_rebuild()

## How wide a blade is at its root, as a share of its own height. Proportional
## rather than absolute, so a short blade is not a wide stub.
@export_range(0.02, 1.0, 0.01) var blade_width: float = 0.35:
	set(value):
		blade_width = clampf(value, 0.02, 1.0)
		_rebuild()

## How far a blade may wander off its own spot, as a share of the gap between
## spots.
##
## **The only thing standing between the lawn and a lattice.** Blades are laid out
## on a sub-grid inside each cell — that is what makes the coverage even and what
## lets a patch of any shape be drawn without storing a single position — and at
## zero that grid is exactly what is drawn. At one each blade fills its own square
## of it and nothing about the layout survives.
##
## Past one they cross into each other's squares, which trades the even coverage
## for clumps and bare ground. A wild verge wants that; a lawn does not.
@export_range(0.0, 2.0, 0.01) var scatter: float = 1.0:
	set(value):
		scatter = clampf(value, 0.0, 2.0)
		_rebuild()

## How far the wind lays a blade over, on top of what the shared wind already
## says. Turf is shorter and stiffer than a tuft, so it takes less of one gust.
@export_range(0.0, 2.0, 0.01) var wind_give: float = 2.0:
	set(value):
		wind_give = clampf(value, 0.0, 2.0)
		_rebuild()

## How far the dark ground fades out past the edge of the patch, in cells.
##
## **The ground only.** The blades stop where the sown cells stop: a patch of
## grass has an edge and pretending otherwise made the whole last metre look
## half-mown. What softens is the darkening under it, so the tile's own colour
## comes back gradually instead of at a line.
##
## Zero is a crisp edge.
@export_range(0.0, 3.0, 0.05) var edge_fade: float = 0.5:
	set(value):
		edge_fade = maxf(value, 0.0)
		_rebuild()

## How far the edge of the grass wanders from where the cells and the obstacles
## put it, in metres.
##
## Both boundaries are worked out as distances, and a boundary drawn from a
## distance is a perfect curve — a straight line along a row of cells, a perfect
## offset around a post. Perfect is the tell. This displaces both by the same
## noise, so the grass stops raggedly and its dark ground stops with it.
##
## Small: this is a ragged edge, not a different shape.
@export_range(0.0, 0.5, 0.005) var edge_jitter: float = 0.08:
	set(value):
		edge_jitter = clampf(value, 0.0, 4)
		_rebuild()

## Metres across one wobble of that edge. Under about a tenth of a metre the
## boundary wanders once per blade, which reads as frayed rather than as irregular.
@export_range(0.05, 4.0, 0.05) var edge_jitter_size: float = 0.55:
	set(value):
		edge_jitter_size = maxf(value, 0.001)
		_rebuild()

## How far grass keeps away from anything else standing on the ground, in metres.
##
## Nothing grows right up against a rock or a fence post: there is a bare ring,
## and drawing it is most of what stops a prop looking dropped on top of a lawn
## rather than standing in it.
##
## What counts as something else: any cell painted on the layer *above* a sown
## one, and any prop node standing beside the grid. Both, because this editor
## offers both ways of putting an object down and an author should not have to
## remember which one they used.
##
## **It is where the grass stops, not where it starts getting shorter.** An earlier
## version scaled a blade by how much room it had, so the lawn tapered over the
## whole of this distance and the ring read as a fade. Grass does not shrink as it
## approaches a rock. The ring is therefore this wide exactly, and reads wider than
## the same number used to.
@export_range(0.0, 3.0, 0.05) var clearance: float = 0.35:
	set(value):
		clearance = maxf(value, 0.0)
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
@export_range(0.0, 1.2, 0.01) var blade_bend: float = 1.0:
	set(value):
		blade_bend = clampf(value, 0.0, 1.2)
		_rebuild()

@export_group("ground")

## How much darker a speck of the ground under the blades is than the ground
## around it.
##
## The mat is one flat colour, and a flat colour under a lawn full of blades reads
## as paper showing through. This stipples it at the blades' own scale, so what
## shows between them has the same busyness they do.
##
## **The look's own roughcast, not a second one.** `comic_look.gdshaderinc` already
## carries a stipple — two octaves of world-space noise cut into specks and faded
## out on their own screen footprint (decision 0065) — built for rendered walls and
## exactly as right for trodden ground. What is turf's own here is only the scale
## it is asked for at.
@export_range(0.0, 0.6, 0.01) var stipple: float = 0.22:
	set(value):
		stipple = clampf(value, 0.0, 0.6)
		_rebuild()

## Metres across one speck. The blades are a couple of centimetres wide and the
## camera is seven metres up, where a pixel covers about seventeen millimetres —
## so below about four centimetres there is nothing left to see and the look's own
## fade correctly removes it.
##
## A tenth of a metre, rendered and looked at. Twice that reads as camouflage: the
## specks become blotches the size of a footprint and the ground stops looking like
## ground with a grain and starts looking like ground with a pattern on it.
@export_range(0.04, 1.0, 0.01) var stipple_size: float = 0.1:
	set(value):
		stipple_size = maxf(value, 0.04)
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

## Each item's footprint at a given height band, in its own space, keyed by item
## and band. Cleared whenever the patch is rebuilt, because a library rebuild can
## change a model under the same id.
var _feet: Dictionary[String, PackedVector2Array] = {}

## The field the shaders read, and the ground it covers. Kept after it is built
## because the mat's own mesh has to be told the same distances the blades get,
## and asking the field is how they agree by construction rather than by two
## calculations happening to match.
var _ground: Image = null
var _ground_area: Rect2 = Rect2()
var _ground_reach: float = 1.0


var _scatter: ShaderMaterial = null
var _blade: ShaderMaterial = null
var _mat: MeshInstance3D = null
var _mat_paint: ShaderMaterial = null


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


## The material that places the blades.
##
## For `TurfTreading`, which writes where somebody is standing into it every frame.
## Handed over rather than having this file learn who is walking: a patch is grown
## from a map and knows nothing about actors, and giving it a second job would put
## the whole world's movement through a node that exists to sow grass.
##
## Null until the patch has been built, which is the honest answer — an unsown
## patch has nothing to press.
func scatter_material() -> ShaderMaterial:
	return _scatter


## Grows the patch again from the map as it stands now.
##
## Everything a patch is made of is already recomputed from scratch whenever one
## of its settings changes; this is the same work, asked for by somebody who
## changed the map instead.
func resow() -> void:
	_rebuild()


## A number that changes when anything this patch was grown from changes.
##
## **Cheap on purpose, because it is read four times a second while the editor is
## open.** It answers "is the map still what it was", not "what is the map" — so it
## walks the same layers `_footprints` does and folds each cell's identity into one
## integer, rather than doing any of the work that follows from them.
##
## What it has to catch is exactly what `_footprints` reads: which cells each layer
## holds, which item is in each, **which way each is turned** — a fence rotated in
## place changes no cell list and changes its whole footprint — and where the prop
## nodes beside the grid are standing.
##
## Returns zero when there is no layer to look at, which is the same answer every
## time and therefore never asks for a rebuild.
func map_signature() -> int:
	var grid: GridMap = get_node_or_null(layer) as GridMap
	if grid == null:
		return 0

	# Folded rather than collected: an array of a few thousand entries to hash
	# would allocate more than the whole rest of this costs.
	var tally: int = cells.size()
	for layer_grid: GridMap in _layers(grid):
		var used: Array[Vector3i] = layer_grid.get_used_cells()
		tally = _fold(tally, used.hash())
		tally = _fold(tally, hash(layer_grid.global_transform))
		tally = _fold(tally, hash(layer_grid.cell_size))
		for cell: Vector3i in used:
			tally = _fold(tally, layer_grid.get_cell_item(cell))
			tally = _fold(tally, layer_grid.get_cell_item_orientation(cell))

	var beside: Node = grid.get_parent()
	if beside == null:
		return tally

	# The models the patch makes way for, at whatever depth they sit. Watching
	# only the grid's direct siblings meant a prop grouped under a node could be
	# moved all day without the lawn ever noticing.
	var models: Array[MeshInstance3D] = []
	for node: Node in beside.get_children():
		_models_under(node, models)
	for shown: MeshInstance3D in models:
		tally = _fold(tally, hash(_relative_to(beside, shown)))

	return tally


## One step of that fold. Masked to thirty-two bits so it cannot overflow, which
## is the one way a signature could differ between two runs on the same map.
static func _fold(tally: int, next: int) -> int:
	return ((tally * 1000003) ^ next) & 0xFFFFFFFF


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
		_lay_mat(null)
		return

	var scatter_shader: Shader = ResourceLoader.load(SCATTER_SHADER, "Shader") as Shader
	var blade_shader: Shader = ResourceLoader.load(BLADE_SHADER, "Shader") as Shader
	if scatter_shader == null or blade_shader == null:
		push_warning("no turf shaders — this patch stays bare")
		return

	_feet.clear()

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
		_lay_mat(null)
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
	var area: Rect2 = _field_area(grid)
	# Built once and handed to both materials. It used to be built here and again
	# in `_lay_mat`, which is the most expensive thing this file does, done twice.
	_ground = _field(grid)
	_ground_area = area
	_ground_reach = _field_reach(grid)
	var room: ImageTexture = ImageTexture.create_from_image(_ground)
	_scatter.set_shader_parameter("room_field", room)
	_scatter.set_shader_parameter("field_origin", area.position)
	_scatter.set_shader_parameter("field_size", area.size)
	_scatter.set_shader_parameter("clearance", clearance)
	_scatter.set_shader_parameter("field_reach", _field_reach(grid))
	_scatter.set_shader_parameter("cell_count", float(filled.size()))
	_scatter.set_shader_parameter("per_cell", float(per_cell))
	_scatter.set_shader_parameter("cell_width", absf(grid.cell_size.x))
	_scatter.set_shader_parameter("cell_depth", absf(grid.cell_size.z))
	_scatter.set_shader_parameter("blade_height", blade_height)
	_scatter.set_shader_parameter("blade_width", blade_width)
	_scatter.set_shader_parameter("height_spread", height_spread)
	_scatter.set_shader_parameter("blade_scatter", scatter)
	_scatter.set_shader_parameter("blade_give", wind_give)
	_scatter.set_shader_parameter("edge_jitter", edge_jitter)
	_scatter.set_shader_parameter("edge_jitter_size", edge_jitter_size)

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
	# After the look: a blade of grass is genuinely flat, and rounding its shading
	# normal towards a sphere would contradict what the eye can see of its edge. No
	# preset names it, so applying it here takes nothing back.
	_blade.set_shader_parameter("shape_round", 0.0)
	_blade.set_shader_parameter("albedo", colour)
	_blade.set_shader_parameter("tip_tint", tip_colour)
	# Full, because the two exported colours *are* the gradient. A partial mix
	# would mean the tip colour the author picked is not the colour they get.
	_blade.set_shader_parameter("tip_tint_amount", 1.0)
	_wear_ground_grain(_blade, grid)
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
	_lay_mat(grid)


## The world-space grain the ground under this patch is wearing, copied onto a
## material so the grass varies with it.
##
## The tile library gives world surfaces patches of slightly darker tone, fixed to
## world space, to break the flatness of a one-colour model. Grass standing on a
## grained tile and not wearing the grain itself is a flat green sheet over a
## varied ground, which is worse than neither having it.
##
## **They line up exactly rather than merely resembling each other**, because both
## read the same function at the same world position: a blade in a darker patch of
## ground is darker by the same amount as the ground it came out of.
##
## Read from the ground rather than exposed, because it is not a choice — it is
## whatever the tile is already doing. A patch whose cells hold nothing grained
## gets nothing, which is the same rule read the other way.
func _wear_ground_grain(onto: ShaderMaterial, grid: GridMap) -> void:
	var amount: float = 0.0
	var size: float = 0.0
	var steps: float = 0.0

	for material: ShaderMaterial in _ground_materials(grid):
		var carried: Variant = material.get_shader_parameter("grain_amount")
		if typeof(carried) != TYPE_FLOAT and typeof(carried) != TYPE_INT:
			continue
		# Through a typed variable rather than a cast: the strict warnings refuse
		# `float()` on a Variant, and an assignment carries the same check.
		var found: float = carried
		if found <= amount:
			continue
		# The strongest wins, so one grained tile in a selection grains the whole
		# patch rather than the answer depending on which cell came first.
		amount = found
		size = _number_on(material, "grain_size", 4.5)
		steps = _number_on(material, "grain_steps", 3.0)

	onto.set_shader_parameter("grain_amount", amount)
	if amount <= 0.0:
		return
	onto.set_shader_parameter("grain_size", size)
	onto.set_shader_parameter("grain_steps", steps)


## Every material drawn under this patch, one per surface of each item sown on.
##
## **Every surface, not the first.** The tile library grains a model surface by
## surface — a tile can have its top grained and its earth band left plain — so
## reading surface zero and stopping found nothing on any model whose ground face
## is not the one that happens to be first.
##
## Each item is read once however many cells hold it: a patch is two thousand
## cells and a handful of models.
func _ground_materials(grid: GridMap) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	if grid.mesh_library == null:
		return found
	var seen: Dictionary[int, bool] = {}
	for cell: Vector3i in _filled:
		var item: int = grid.get_cell_item(cell)
		if item == GridMap.INVALID_CELL_ITEM or seen.has(item):
			continue
		seen[item] = true
		var mesh: Mesh = grid.mesh_library.get_item_mesh(item)
		if mesh == null:
			continue
		for surface: int in range(mesh.get_surface_count()):
			var material: ShaderMaterial = mesh.surface_get_material(surface) as ShaderMaterial
			if material != null:
				found.append(material)
	return found


## One shader value off a material, or the fallback when it carries none.
static func _number_on(material: ShaderMaterial, name: String, fallback: float) -> float:
	var carried: Variant = material.get_shader_parameter(name)
	if typeof(carried) != TYPE_FLOAT and typeof(carried) != TYPE_INT:
		return fallback
	var found: float = carried
	return found


## Lays a dark mat over the sown cells, so the ground under the blades is the
## colour of their roots rather than whatever the tile happens to be.
##
## **A mat and not a tint on the tile.** A `GridMap` gives one material to every
## cell that holds the same item, so darkening it would darken that tile
## everywhere on the map — including the cells nobody sowed. The mat belongs to
## this patch, covers exactly the cells this patch sowed, and leaves with it.
##
## The node is deliberately not given an owner, so it is never saved: it is grown
## from the cells like everything else here, and a scene carrying it would be a
## scene carrying geometry.
func _lay_mat(grid: GridMap) -> void:
	if grid == null:
		if _mat != null:
			_mat.visible = false
		return

	if _mat == null:
		_mat = MeshInstance3D.new()
		_mat.name = "Mat"
		add_child(_mat)
	_mat.visible = true

	var mat_shader: Shader = ResourceLoader.load(MAT_SHADER, "Shader") as Shader
	if mat_shader == null:
		push_warning("no mat shader — the ground under this turf stays as it is")
		_mat.visible = false
		return

	if _mat_paint == null:
		_mat_paint = ShaderMaterial.new()
	_mat_paint.shader = mat_shader
	_mat_paint.set_shader_parameter("albedo", colour)
	# In metres, because the shader works in metres: the author sets the fade in
	# cells and a cell is only a cell wide on a grid whose spacing is one.
	_mat_paint.set_shader_parameter("edge_width", edge_fade * absf(grid.cell_size.x))
	# The same field the blades read, and the same wander laid over it, so the dark
	# ground stops exactly where the grass does — including the ring around anything
	# standing on it, and including where that ring is nibbled.
	_mat_paint.set_shader_parameter(
		"room_field", ImageTexture.create_from_image(_ground)
	)
	var area: Rect2 = _field_area(grid)
	_mat_paint.set_shader_parameter("field_origin", area.position)
	_mat_paint.set_shader_parameter("field_size", area.size)
	_mat_paint.set_shader_parameter("clearance", clearance)
	_mat_paint.set_shader_parameter("field_reach", _field_reach(grid))
	_mat_paint.set_shader_parameter("edge_jitter", edge_jitter)
	_mat_paint.set_shader_parameter("edge_jitter_size", edge_jitter_size)
	_mat_paint.set_shader_parameter("shape_round", 0.0)
	var look: Dictionary[String, Variant] = CreatureView.preset_values(
		CreatureView.roster_style()
	)
	for name: String in look:
		if name != "albedo":
			_mat_paint.set_shader_parameter(name, look[name])
	_wear_ground_grain(_mat_paint, grid)
	# After the preset, so the patch's own scale wins over whatever the shared look
	# is currently tuned for. Two octaves an octave apart, which is the spacing the
	# roughcast is tuned at everywhere else: an aggregate you can see and a sand you
	# can only feel.
	_mat_paint.set_shader_parameter("stucco_amount", stipple)
	_mat_paint.set_shader_parameter("stucco_coarse", 1.0 / stipple_size)
	_mat_paint.set_shader_parameter("stucco_fine", 2.0 / stipple_size)

	_mat.mesh = _mat_mesh(grid)
	_mat.material_override = _mat_paint
	_mat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## One quad per sown cell, lying on that cell's own surface, each corner carrying
## how covered it is.
##
## **The distance is what makes the edge a fade rather than a rectangle.** Each
## corner carries how far inside the sown area it is, in metres, and the shader
## turns that into the alpha over whatever fade width the author asked for. The mat
## therefore dissolves at the edge of the grass and follows whatever shape was
## selected, including a diagonal or a hole.
##
## It travels in the **second UV set** rather than in the vertex colour, which is
## where it used to live: a colour is eight bits clamped to one, so it could carry
## a coverage and not a distance. The blades read the same distances out of a float
## texture, and a boundary the two disagree about is a halo.
##
## Winding is not fussed over because the mat shader culls nothing — a mat seen
## from below is a mat, and there is nothing under it to see.
func _mat_mesh(grid: GridMap) -> ArrayMesh:
	var points: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var edges: PackedVector2Array = PackedVector2Array()
	var faces: PackedInt32Array = PackedInt32Array()

	var half_x: float = absf(grid.cell_size.x) * 0.5
	var half_z: float = absf(grid.cell_size.z) * 0.5

	for cell: Vector3i in _filled:
		var at: Vector3 = grid.map_to_local(cell)
		var up: float = _surface_of(grid, cell) + MAT_LIFT
		var first: int = points.size()
		for corner: int in range(4):
			var dx: int = -1 if corner % 2 == 0 else 1
			var dz: int = -1 if corner < 2 else 1
			points.append(Vector3(at.x + float(dx) * half_x, up, at.z + float(dz) * half_z))
			normals.append(Vector3.UP)
			uvs.append(Vector2(0.5, 0.0))
			edges.append(Vector2(_inside_at(Vector2(
				at.x + float(dx) * half_x, at.z + float(dz) * half_z
			)), 0.0))
		faces.append_array([first, first + 2, first + 1])
		faces.append_array([first + 1, first + 2, first + 3])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = edges
	arrays[Mesh.ARRAY_INDEX] = faces

	var mat: ArrayMesh = ArrayMesh.new()
	mat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mat


## Every sown cell's own origin, as a texture the scatter reads by index.
##
## A texture and not an array uniform because a patch may carry hundreds of cells
## and an array has a ceiling written into the shader. One texel per cell,
## unfiltered, so what is read back is what was written.
##
## It used to carry a second row of corner distances as well, which is how a blade
## knew where the edge of the patch was. The edge is in the field now, at texel
## resolution rather than at cell resolution, so a blade reads it at its own feet
## exactly as it already read the room around an obstacle.
func _spots(grid: GridMap) -> ImageTexture:
	var spots: Image = Image.create(maxi(_filled.size(), 1), 1, false, Image.FORMAT_RGBF)
	for index: int in range(_filled.size()):
		var cell: Vector3i = _filled[index]
		var at: Vector3 = grid.map_to_local(cell)
		spots.set_pixel(index, 0, Color(at.x, _surface_of(grid, cell), at.z))
	return ImageTexture.create_from_image(spots)


## Everything the shaders have to know about the ground under this patch, in one
## texture read once per blade and once per fragment.
##
## | | |
## |---|---|
## | **R** | how far from the nearest obstacle, 0 inside one |
## | **G** | how far inside the grass, 0 anywhere outside it |
## | **B** | how far outside the grass, 0 anywhere inside it |
##
## G and B are one signed distance in two unsigned channels, because an eight-bit
## texture cannot hold a negative and the sign is what says which side of the edge
## a blade is on. Their difference is the answer.
##
## **The edge of the grass is measured, not counted.** It used to be worked out per
## corner of each cell, in cells, which could only ever describe a boundary that
## ran along cell walls. Measured here it is a distance like the other one, on the
## same grid, at texel resolution — so the same code will describe a boundary
## painted freehand without knowing that anything changed.
##
## **A distance to the shape of a thing, not to a circle around it.** A radius put
## a round bare ring around a square platform; what an author means by "keep half
## a metre away" is half a metre from its *edge*, so the grass follows a corner
## round a corner and a straight edge in a straight line.
##
## Stored as a share of `_field_reach` rather than in metres, so a texel is the
## same size whatever the clearance and the shader multiplies once to get metres
## back.
func _field(grid: GridMap) -> Image:
	var area: Rect2 = _field_area(grid)
	var wide: int = clampi(roundi(area.size.x * FIELD_DETAIL), 1, FIELD_MOST)
	var deep: int = clampi(roundi(area.size.y * FIELD_DETAIL), 1, FIELD_MOST)
	var reach: float = _field_reach(grid)

	# Texels the obstacles cover. Zero room there, and the seed of the first
	# distance. Skipped entirely when nothing is kept away from anything.
	var room: PackedFloat32Array = PackedFloat32Array()
	if clearance > 0.0:
		var blocked: PackedByteArray = PackedByteArray()
		blocked.resize(wide * deep)
		for print_of: PackedVector2Array in _footprints(grid):
			_stamp(blocked, wide, deep, area, print_of)
		room = _gap(blocked, wide, deep, area, reach)

	var grown: PackedByteArray = _grass(grid, wide, deep, area)
	var bare: PackedByteArray = PackedByteArray()
	bare.resize(wide * deep)
	for index: int in range(wide * deep):
		bare[index] = 0 if grown[index] == 1 else 1

	# Two sweeps of the same measurement from opposite stencils: how far this texel
	# is from the nearest bare one, and how far from the nearest grassy one. One of
	# the two is always zero, which is what makes the difference a signed distance.
	var into: PackedFloat32Array = _gap(bare, wide, deep, area, reach)
	var out_of: PackedFloat32Array = _gap(grown, wide, deep, area, reach)

	# **Half a texel off every distance.** A chamfer measures from texel centre to
	# texel centre, so the texel just inside a boundary comes back a whole texel
	# from the one just outside it and the boundary itself is nowhere — the field
	# steps from plus a texel to minus a texel with nothing between. Taking half a
	# texel off both sides puts the zero where the edge actually is.
	var half: float = (area.size.x / float(wide) + area.size.y / float(deep)) * 0.25

	var field: Image = Image.create(wide, deep, false, Image.FORMAT_RGBA8)
	for y: int in range(deep):
		for x: int in range(wide):
			var index: int = y * wide + x
			var free: float = 1.0
			if not room.is_empty():
				free = clampf((room[index] - half) / reach, 0.0, 1.0)
			field.set_pixel(x, y, Color(
				free,
				clampf((into[index] - half) / reach, 0.0, 1.0),
				clampf((out_of[index] - half) / reach, 0.0, 1.0),
				1.0
			))
	return field


## Which texels have grass on them.
##
## One byte per texel rather than a coverage, because what follows is a distance
## and a distance needs a boundary to start from, not a gradient. A texel belongs
## to the grass when its middle lies in a sown cell.
##
## Filled cell by cell rather than texel by texel: a patch is a few hundred cells
## and a hundred thousand texels, and asking each texel which cell it is in would
## be the same answer arrived at the expensive way.
func _grass(grid: GridMap, wide: int, deep: int, area: Rect2) -> PackedByteArray:
	var grown: PackedByteArray = PackedByteArray()
	grown.resize(wide * deep)

	var half: Vector2 = Vector2(absf(grid.cell_size.x), absf(grid.cell_size.z)) * 0.5
	for cell: Vector3i in _filled:
		var at: Vector3 = grid.map_to_local(cell)
		var low: Vector2 = Vector2(at.x, at.z) - half
		var high: Vector2 = Vector2(at.x, at.z) + half
		var from_x: int = clampi(
			ceili((low.x - area.position.x) / area.size.x * float(wide) - 0.5), 0, wide - 1
		)
		var to_x: int = clampi(
			floori((high.x - area.position.x) / area.size.x * float(wide) - 0.5), 0, wide - 1
		)
		var from_y: int = clampi(
			ceili((low.y - area.position.y) / area.size.y * float(deep) - 0.5), 0, deep - 1
		)
		var to_y: int = clampi(
			floori((high.y - area.position.y) / area.size.y * float(deep) - 0.5), 0, deep - 1
		)
		for y: int in range(from_y, to_y + 1):
			for x: int in range(from_x, to_x + 1):
				grown[y * wide + x] = 1
	return grown


## How far inside the grass a point on the ground is, in metres, read out of the
## field the blades read.
##
## **Asked of the field rather than worked out again.** The mat and the blades have
## to stop on the same line, and two calculations that agree today are two
## calculations that can stop agreeing. One of them is the answer and the other
## reads it.
##
## Sampled at the nearest texel: the mat's own vertices land on cell corners, which
## the field grid is aligned to, so there is nothing between texels to interpolate.
func _inside_at(at: Vector2) -> float:
	if _ground == null:
		return 0.0
	var wide: int = _ground.get_width()
	var deep: int = _ground.get_height()
	var x: int = clampi(floori(
		(at.x - _ground_area.position.x) / _ground_area.size.x * float(wide)
	), 0, wide - 1)
	var y: int = clampi(floori(
		(at.y - _ground_area.position.y) / _ground_area.size.y * float(deep)
	), 0, deep - 1)
	var found: Color = _ground.get_pixel(x, y)
	return (found.g - found.b) * _ground_reach


## The longest distance the room field can express, in metres.
##
## The clearance is where the grass stops, and the ground under it fades out over
## `edge_fade` *inside* that — so the field has to reach past the clearance by at
## least the fade, or the ground would still be at full strength where the last
## blade is. The wander is added because it moves the boundary outward as readily
## as inward.
func _field_reach(grid: GridMap) -> float:
	return maxf(
		clearance + edge_fade * absf(grid.cell_size.x) + edge_jitter, 0.01
	)


## The ground this field covers: the sown cells, grown by the clearance so the
## ring around an obstacle at the very edge is not cut off.
func _field_area(grid: GridMap) -> Rect2:
	var box: Rect2 = Rect2(Vector2(grid.map_to_local(_filled[0]).x, grid.map_to_local(_filled[0]).z), Vector2.ZERO)
	var half: Vector2 = Vector2(absf(grid.cell_size.x), absf(grid.cell_size.z)) * 0.5
	for cell: Vector3i in _filled:
		var at: Vector3 = grid.map_to_local(cell)
		box = box.expand(Vector2(at.x, at.z) - half)
		box = box.expand(Vector2(at.x, at.z) + half)
	return box.grow(clearance + 0.5)


## Every obstacle's footprint, as triangles on the ground in the grid's space.
##
## Taken from the model's own base triangles — those wholly in its bottom fifth —
## so the shape is the thing's, not its bounding box's. Cached per item, because
## a patch meets the same handful of models over and over and walking a mesh is
## the one expensive thing in this file.
func _footprints(grid: GridMap) -> Array[PackedVector2Array]:
	var stamps: Array[PackedVector2Array] = []
	if _filled.is_empty():
		return stamps

	var sown: Dictionary[Vector3i, bool] = {}
	for cell: Vector3i in _filled:
		sown[cell] = true
	var floor_y: float = grid.map_to_local(_filled[0]).y

	for layer_grid: GridMap in _layers(grid):
		for cell: Vector3i in layer_grid.get_used_cells():
			if layer_grid == grid and sown.has(cell):
				continue
			var at: Vector3 = grid.to_local(
				layer_grid.to_global(layer_grid.map_to_local(cell))
			)
			# **The height test belongs to the sown layer alone.** On that layer it
			# separates a second storey from the ground itself; on any other it
			# separates nothing, because a blocking or decor layer holds only
			# things. Applying it everywhere is what made the delimitation miss a
			# well painted on decor at the same height as the terrain — which is
			# where most props are painted, so it missed nearly all of them.
			#
			# What decides for the other layers is the slice below: a cell with no
			# geometry at the height of a blade stamps nothing and costs a lookup.
			if layer_grid == grid and at.y <= floor_y + 0.01:
				continue
			# The slab this obstacle has to be sliced at: from a little under the
			# ground the grass stands on, to the top of the tallest blade. In the
			# model's own space, because that is where its vertices are — and a
			# `GridMap` draws an item at `cell_scale` about the cell's origin.
			var ground: float = _ground_under(grid, sown, at, floor_y)
			var scale: float = maxf(layer_grid.cell_scale, 0.0001)
			# **From where the thing stands, up to where the grass ends.**
			#
			# The grass surface alone is not enough, and the reason is worth
			# keeping: a leafy ground tile's surface is the top of its own leaves —
			# 1.13 m above the cell on the quarantined pack — while a prop is drawn
			# at its cell's origin. Slicing only at the grass height put the slab a
			# metre above every prop on the map, so nothing was ever stamped and the
			# delimitation quietly did nothing at all.
			var from_y: float = minf(ground - SLICE_BELOW, at.y)
			var low: float = (from_y - at.y) / scale
			var high: float = (
				ground + maxf(blade_height + lift, SLICE_ABOVE) - at.y
			) / scale
			var shape: PackedVector2Array = _slice_of(layer_grid, cell, low, high)
			if shape.is_empty():
				continue
			var here: Vector2 = Vector2(at.x, at.z)
			# **Turned the way the cell is turned.** A `GridMap` stores one of
			# twenty-four orientations per cell, and a fence painted sideways has a
			# footprint that is long the other way. Reading the shape and not the
			# turn gave a clearance at right angles to the thing it was for.
			var facing: Basis = layer_grid.get_basis_with_orthogonal_index(
				layer_grid.get_cell_item_orientation(cell)
			)
			var placed: PackedVector2Array = PackedVector2Array()
			for corner: Vector2 in shape:
				var turned: Vector3 = facing * Vector3(corner.x, 0.0, corner.y)
				placed.append(here + Vector2(turned.x, turned.z) * scale)
			stamps.append(placed)

	var beside: Node = grid.get_parent()
	if beside == null:
		return stamps

	# **Every model on the map, at any depth.** This used to read the grid's direct
	# siblings only, so grouping props under a node — which is the first thing
	# anybody does with more than three of them — quietly stopped clearing grass
	# around any of them.
	var models: Array[MeshInstance3D] = []
	for node: Node in beside.get_children():
		_models_under(node, models)

	# Into the sown grid's space, which is what everything above is measured in.
	# The models are the grid's siblings, so walking up from one reaches the map
	# rather than the grid, and the grid's own place has to be taken back out.
	var into_grid: Transform3D = grid.transform.affine_inverse()

	for shown: MeshInstance3D in models:
		var at: Transform3D = into_grid * _relative_to(beside, shown)
		var ground: float = _ground_under(grid, sown, at.origin, floor_y)
		# **Its real shape at blade height, not its bounding box.** A box is as
		# wide as a tree's canopy, so a tree cleared a square of lawn the size of
		# its crown with nothing standing in most of it. That was tolerable while
		# a model placed as a node was a rarity; a prop is now the ordinary way to
		# put something on a map, so the crude path had become the main one.
		var shape: PackedVector2Array = _stamp_of(
			shown.mesh,
			at,
			minf(ground - SLICE_BELOW, at.origin.y),
			ground + maxf(blade_height + lift, SLICE_ABOVE)
		)
		if not shape.is_empty():
			stamps.append(shape)

	return stamps


## Every model under a node, skipping the grids and whatever grows cover.
##
## **Its own walk, not `VltFootprint`'s.** The shape is the same and the rule is
## not: this one drops a grid and a cover-grower *at every level*, because a
## patch grouped under a node is still not an obstacle to a patch — and the
## blocking shapes have no such exception to make. Handing the difference over as
## a predicate would be one walk with a parameter nobody reading either caller
## could resolve.
##
## A hidden branch is skipped whole: grass makes way for what is there, and
## something switched off is not there. The local flag is enough because the walk
## is top-down and never reaches a hidden node's children.
static func _models_under(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is GridMap or _grows_cover(node):
		return

	var branch: Node3D = node as Node3D
	if branch != null and not branch.visible:
		return

	var part: MeshInstance3D = node as MeshInstance3D
	if part != null and part.mesh != null:
		into.append(part)

	for child: Node in node.get_children():
		_models_under(child, into)


## Where a node stands relative to an ancestor.
##
## Local transforms multiplied rather than `global_transform`, which needs a
## scene tree — and a patch is measured in tests and in the editor's own
## rebuild, neither of which guarantees one.
static func _relative_to(root: Node, node: Node3D) -> Transform3D:
	var at: Transform3D = Transform3D.IDENTITY
	var walk: Node3D = node

	while walk != null and walk != root:
		at = walk.transform * at
		walk = walk.get_parent() as Node3D

	return at


## Whether a node beside the grid is itself something that grows ground cover.
##
## The rule used to be `node == self`, which said the right thing about one node
## and nothing at all about its neighbours. A patch is not an obstacle to a patch:
## turf does not have to make way for turf, and foliage is leaves sitting on
## models whose own cells are stamped a few lines above — clearing a second time
## around them eats exactly the lawn they were put there to stand in.
static func _grows_cover(node: Node) -> bool:
	return node is TurfPatch or node is VltFoliagePatch


## The height of the grass directly under an obstacle, which is the height its
## footprint has to be sliced at.
##
## Asked of the sown cell beneath it, so a patch covering a flat tile and a raised
## block slices what stands on each at its own ground. Falls back to the patch's
## own floor when nothing was sown under it — an obstacle on the far side of a
## hole still needs an answer.
func _ground_under(
	grid: GridMap, sown: Dictionary[Vector3i, bool], at: Vector3, floor_y: float
) -> float:
	# **Found by where it is, not by counting cells down.** A layer carries its own
	# transform, so a prop painted at cell y = 0 on the blocking layer can stand at
	# 1.65 in the terrain's space. Stepping down in grid coordinates then looks for
	# a sown cell at y = -1 and finds nothing, and the ground falls back to the
	# patch's floor — which put the slice more than two metres below every model on
	# the map and made the delimitation stamp nothing at all.
	var mapped: Vector3i = grid.local_to_map(at)
	var under: Vector3i = Vector3i(mapped.x, _filled[0].y, mapped.z)
	if sown.has(under):
		return _surface_of(grid, under)
	return floor_y


## Every `GridMap` of the map this patch belongs to, the sown one included.
##
## Every layer, not only the sown one: a map is three of them — terrain, blocking,
## decor — and a tree is painted on one of the other two. Looking only at the
## layer being sown found nothing, which is why the grass grew against the trunks.
static func _layers(grid: GridMap) -> Array[GridMap]:
	var found: Array[GridMap] = []
	var beside: Node = grid.get_parent()
	if beside == null:
		return [grid] as Array[GridMap]
	for node: Node in beside.get_children():
		var layer_grid: GridMap = node as GridMap
		if layer_grid != null:
			found.append(layer_grid)
	return found if not found.is_empty() else [grid] as Array[GridMap]


## What a model looks like **at the height the grass stands**, flattened to the
## ground, in the model's own space.
##
## This is the whole of the delimitation and it took three tries to get right, so
## the reasoning is worth keeping.
##
## The first rule was "the bottom fifth of the model". That is a proportion of the
## *object*, and it has nothing to do with where the grass is. Measured across the
## quarantined pack it is wrong more often than right: `Gem_Spawner` starts 0.73 m
## below the ground and its bottom fifth is entirely inside its own pit, so the
## rim at ground level was never seen and grass grew over the well and into the
## hole. `Spawn_Gem` is the same. `SpawnZone` has zero height and the rule is
## degenerate on it. A palm worked by luck.
##
## The rule here instead: **the slab a blade occupies**. From a little under the
## ground the grass stands on, to the top of the tallest blade. That is literally
## what a blade would run into, so it is right by construction rather than by
## being tuned — a well gives its rim, a palm gives its trunk, a crate gives its
## whole box, a plane gives itself, and something floating overhead gives nothing
## and lets grass grow under it.
##
## **Triangles are clipped to the slab, not merely tested against it.** A low-poly
## trunk can be one triangle running from the ground to the canopy; including it
## whole would project the canopy and carve a crater, and excluding it would leave
## the trunk unseen. Clipping takes the part that is actually in the way.
func _slice_of(
	grid: GridMap, cell: Vector3i, low: float, high: float
) -> PackedVector2Array:
	if grid.mesh_library == null:
		return PackedVector2Array()
	var item: int = grid.get_cell_item(cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return PackedVector2Array()

	# Keyed on the band as well as the item: the same model on two different
	# layers meets the grass at two different heights, and one cached answer for
	# both would be wrong for at least one of them.
	var key: String = "%d:%d:%d" % [item, roundi(low * 64.0), roundi(high * 64.0)]
	if _feet.has(key):
		return _feet[key]

	var mesh: ArrayMesh = grid.mesh_library.get_item_mesh(item) as ArrayMesh
	if mesh == null:
		return PackedVector2Array()

	# In the model's own space: a cell applies its turn, its scale and its
	# position afterwards, which is what lets one answer serve every cell holding
	# the item.
	var solid: PackedVector2Array = _stamp_of(mesh, Transform3D.IDENTITY, low, high)
	_feet[key] = solid
	return solid


## The same slice, for a model already standing somewhere.
##
## **The triangles are put where they stand before anything is measured.** A prop
## carries its own rotation and scale, and the slab is a pair of heights in the
## world — so slicing in the model's units and transforming afterwards would only
## agree with this for something upright and uniformly scaled.
##
## The grid keeps the identity case and keeps its cache with it: the same item in
## a hundred cells is measured once and placed a hundred times, which is what
## makes a patch over a tiled field affordable.
func _stamp_of(
	mesh: Mesh, at: Transform3D, low: float, high: float
) -> PackedVector2Array:
	var flat: PackedVector2Array = PackedVector2Array()

	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if typeof(arrays[Mesh.ARRAY_VERTEX]) != TYPE_PACKED_VECTOR3_ARRAY:
			continue
		@warning_ignore("unsafe_cast")
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		var faces: PackedInt32Array = PackedInt32Array()
		if typeof(arrays[Mesh.ARRAY_INDEX]) == TYPE_PACKED_INT32_ARRAY:
			@warning_ignore("unsafe_cast")
			faces = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		else:
			# An unindexed surface is three points a triangle, in order. Handled
			# rather than skipped: skipping one silently would leave a model with
			# no footprint and grass growing through it.
			for index: int in range(points.size()):
				faces.append(index)

		var corner: int = 0
		while corner + 2 < faces.size():
			var whole: Array[Vector3] = [
				at * points[faces[corner]],
				at * points[faces[corner + 1]],
				at * points[faces[corner + 2]],
			]
			corner += 3
			var inside: Array[Vector3] = _slab(whole, low, high)
			if inside.size() < 3:
				continue
			# Fanned from the first corner: the clip of a triangle by two parallel
			# planes is convex, so a fan is a correct triangulation of it.
			for step: int in range(1, inside.size() - 1):
				flat.append(Vector2(inside[0].x, inside[0].z))
				flat.append(Vector2(inside[step].x, inside[step].z))
				flat.append(Vector2(inside[step + 1].x, inside[step + 1].z))

	# **Solid, not hollow.** A slice through a well at grass height is a ring: its
	# walls are in the slab and its middle is not, so stamping the slice as it
	# comes leaves the inside of the well open and grass grows in the hole. What a
	# blade has to stay out of is the whole area the thing occupies, so the slice
	# is closed over its own hull.
	#
	# Convex, which fills the notch of an L and the mouth of a U. That is the right
	# way to be wrong here: a little too much bare ground reads as deliberate, and
	# grass growing inside a well reads as broken.
	var hull: PackedVector2Array = Geometry2D.convex_hull(flat)
	var solid: PackedVector2Array = PackedVector2Array()
	for step: int in range(1, hull.size() - 1):
		solid.append(hull[0])
		solid.append(hull[step])
		solid.append(hull[step + 1])

	return solid


## A polygon kept to the part of it between two heights.
static func _slab(poly: Array[Vector3], low: float, high: float) -> Array[Vector3]:
	var kept: Array[Vector3] = _cut(poly, low, true)
	if kept.size() < 3:
		return []
	return _cut(kept, high, false)


## A polygon cut by one horizontal plane, keeping the side asked for.
##
## Sutherland and Hodgman, on one axis. A corner on the kept side survives, and an
## edge that crosses gains a corner where it crosses — which is what stops a
## triangle from being all-or-nothing.
static func _cut(poly: Array[Vector3], at: float, above: bool) -> Array[Vector3]:
	var kept: Array[Vector3] = []
	var count: int = poly.size()
	for index: int in range(count):
		var here: Vector3 = poly[index]
		var next: Vector3 = poly[(index + 1) % count]
		var here_in: bool = here.y >= at if above else here.y <= at
		var next_in: bool = next.y >= at if above else next.y <= at
		if here_in:
			kept.append(here)
		if here_in != next_in:
			# Safe: the two differ, so their heights differ and this cannot divide
			# by zero.
			kept.append(here.lerp(next, (at - here.y) / (next.y - here.y)))
	return kept


## Marks every texel a footprint covers.
##
## Plain barycentric coverage over each triangle's own bounding box. Nothing
## clever: the grids are a couple of hundred texels across and this runs when a
## patch is edited, not when it is drawn.
static func _stamp(
	taken: PackedByteArray, wide: int, deep: int, area: Rect2, shape: PackedVector2Array
) -> void:
	var corner: int = 0
	while corner + 2 < shape.size():
		var a: Vector2 = shape[corner]
		var b: Vector2 = shape[corner + 1]
		var c: Vector2 = shape[corner + 2]
		corner += 3

		var low: Vector2 = Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
		var high: Vector2 = Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
		var from_x: int = clampi(floori((low.x - area.position.x) / area.size.x * float(wide)), 0, wide - 1)
		var to_x: int = clampi(ceili((high.x - area.position.x) / area.size.x * float(wide)), 0, wide - 1)
		var from_y: int = clampi(floori((low.y - area.position.y) / area.size.y * float(deep)), 0, deep - 1)
		var to_y: int = clampi(ceili((high.y - area.position.y) / area.size.y * float(deep)), 0, deep - 1)

		var turn: float = (b - a).cross(c - a)
		if absf(turn) < 1e-9:
			continue

		for y: int in range(from_y, to_y + 1):
			for x: int in range(from_x, to_x + 1):
				var at: Vector2 = Vector2(
					area.position.x + (float(x) + 0.5) / float(wide) * area.size.x,
					area.position.y + (float(y) + 0.5) / float(deep) * area.size.y
				)
				var one: float = (b - a).cross(at - a) / turn
				var two: float = (c - b).cross(at - b) / turn
				var three: float = (a - c).cross(at - c) / turn
				if one >= 0.0 and two >= 0.0 and three >= 0.0:
					taken[y * wide + x] = 1


## Fills in how far every texel is from the nearest covered one, as a share of the
## clearance.
##
## Two sweeps of a chamfer, forwards then backwards, which is the ordinary way to
## get a distance out of a stencil without measuring every pair. Exact enough: the
## error is under a texel, and a texel here is a few centimetres.
func _gap(
	taken: PackedByteArray, wide: int, deep: int, area: Rect2, reach: float
) -> PackedFloat32Array:
	var step_x: float = area.size.x / float(wide)
	var step_y: float = area.size.y / float(deep)
	var across: float = sqrt(step_x * step_x + step_y * step_y)
	var far: float = reach * 4.0

	var gap: PackedFloat32Array = PackedFloat32Array()
	gap.resize(wide * deep)
	for index: int in range(wide * deep):
		gap[index] = 0.0 if taken[index] == 1 else far

	for y: int in range(deep):
		for x: int in range(wide):
			var here: int = y * wide + x
			if x > 0:
				gap[here] = minf(gap[here], gap[here - 1] + step_x)
			if y > 0:
				gap[here] = minf(gap[here], gap[here - wide] + step_y)
			if x > 0 and y > 0:
				gap[here] = minf(gap[here], gap[here - wide - 1] + across)
			if x + 1 < wide and y > 0:
				gap[here] = minf(gap[here], gap[here - wide + 1] + across)

	for y: int in range(deep - 1, -1, -1):
		for x: int in range(wide - 1, -1, -1):
			var here: int = y * wide + x
			if x + 1 < wide:
				gap[here] = minf(gap[here], gap[here + 1] + step_x)
			if y + 1 < deep:
				gap[here] = minf(gap[here], gap[here + wide] + step_y)
			if x + 1 < wide and y + 1 < deep:
				gap[here] = minf(gap[here], gap[here + wide + 1] + across)
			if x > 0 and y + 1 < deep:
				gap[here] = minf(gap[here], gap[here + wide - 1] + across)

	return gap


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
