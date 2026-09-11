@tool
class_name VltFoliagePatch
extends MeshInstance3D

## Leaves on the cells somebody chose, with the settings they chose at the time.
##
## **Nothing in this game has foliage unless one of these says so.** There is no
## automatic pass, no name to match, no default: a map with no patch has bare
## models, which is the state every map starts in and stays in until an author
## acts.
##
## One node is one application. Sowing a selection makes a patch; sowing another
## selection with different numbers makes a second patch beside it. That is what
## makes the settings "at the time" real rather than a claim — they are `@export`s
## on this node, so they belong to this application and to no other, and changing
## one re-sows only these cells. Deleting the node takes its leaves with it and
## leaves the models exactly as they were.
##
## **It stores cells and numbers, never a mesh.** Six floats and a list of cells
## go into the `.tscn`; the leaves are grown again on load, which is only possible
## because the sowing is deterministic (`VltFoliage`). A map with two hundred sown
## cells costs a few kilobytes of scene rather than a few megabytes of geometry.
##
## The bare model is still drawn by the `GridMap` underneath. This lays leaves
## *over* it and owns nothing else, which is why removing it cannot leave a hole.

## The layer whose cells these are, and whose palette says what grows where.
##
## A patch reads the item at each cell and sows that item's own mesh, so one patch
## can cover a palm and a bush and each gets its own foliage without being told.
@export var layer: NodePath:
	set(value):
		layer = value
		_regrow()

## Which cells. Grid coordinates, the same ones the `GridMap` editor selects.
@export var cells: Array[Vector3i] = []:
	set(value):
		cells = value
		_regrow()

## Shifts every seed at once, so a patch that came out badly can be rerolled
## without being redrawn.
@export var seed: int = 0:
	set(value):
		seed = value
		_regrow()

@export_group("sowing")

## Leaves per square unit of the model's own space — see `VltFoliage.Settings`.
##
## `or_greater`, so the slider is a useful range and not a ceiling: nothing in the
## generator caps this, and the two numbers it was pinned at before were both
## picked out of the air. What it does cost is linear — a palm's canopy is about
## 126 square units, so every point of density is another 126 leaves on every cell
## carrying one, and a leaf is six vertices and eight triangles.
@export_range(0.0, 200.0, 0.1, "or_greater") var density: float = 500.0:
	set(value):
		density = value
		_regrow()

## What colour the leaves are, and how much of it they take. At zero a leaf is
## exactly the colour of the surface it grew on, which is what a patch does until
## somebody says otherwise.
@export var colour: Color = Color(0.42, 0.72, 0.34):
	set(value):
		colour = value
		_regrow()

@export_range(0.0, 1.0, 0.01) var colour_amount: float = 0.0:
	set(value):
		colour_amount = value
		_regrow()

## Leaf length as a share of the model's own height, so one setting suits a palm
## and a cactus alike.
@export_range(0.005, 0.5, 0.005) var smallest: float = 0.05:
	set(value):
		smallest = value
		_regrow()

@export_range(0.005, 0.5, 0.005) var largest: float = 0.09:
	set(value):
		largest = value
		_regrow()

@export_range(0.0, 90.0, 1.0) var lean: float = 90.0:
	set(value):
		lean = value
		_regrow()

@export_range(0.0, 1.0, 0.01) var lift: float = 0.0:
	set(value):
		lift = value
		_regrow()

@export_group("wind")

## How much this foliage answers the one wind, and where a leaf is held.
##
## **The wind itself is not a patch's to set.** Its direction, its gust and its
## breath are the world's, shared with the grass and the turf, and global by
## decision 0061. What a patch says is how hard *its* leaves answer: a sheltered
## bush barely stirs, a crown on a ridge sweeps, and zero is perfectly still.
@export_range(0.0, 60.0, 0.5) var sway: float = 10.0:
	set(value):
		sway = value
		_regrow()

@export_range(0.0, 0.6, 0.01) var stem_hold: float = 0.15:
	set(value):
		stem_hold = value
		_regrow()

@export_group("sowing")

## How large a surface must be against the model's largest to be sown at all.
## Keeps leaves off a palm's trunk; drop it to zero to sow everything.
@export_range(0.0, 1.0, 0.01) var dominant_share: float = 0.5:
	set(value):
		dominant_share = value
		_regrow()


func _ready() -> void:
	_regrow()


## How many leaves this patch is carrying. For a report, and for an author who
## wants to know what a density is costing before a profiler tells them.
func leaf_total() -> int:
	if mesh == null:
		return 0
	var vertices: int = 0
	for surface: int in range(mesh.get_surface_count()):
		@warning_ignore("unsafe_cast")
		var points: PackedVector3Array = (
			mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		)
		vertices += points.size()
	return vertices / VltFoliage.OUTLINE.size()


## Settings as the generator wants them.
func settings() -> VltFoliage.Settings:
	var wanted: VltFoliage.Settings = VltFoliage.Settings.new()
	wanted.density = density
	wanted.smallest = smallest
	wanted.largest = largest
	wanted.lean = lean
	wanted.lift = lift
	wanted.dominant_share = dominant_share
	wanted.colour = colour
	wanted.colour_amount = colour_amount
	wanted.sway = sway
	wanted.stem_hold = stem_hold
	return wanted


## Grows every cell's leaves and merges them into this node's one mesh.
##
## One mesh and not one node per cell: a hundred sown cells would otherwise be a
## hundred nodes in the scene tree and a hundred draw calls, and nothing about a
## leaf needs to be addressable on its own.
func _regrow() -> void:
	if not is_inside_tree():
		return

	var grid: GridMap = get_node_or_null(layer) as GridMap
	if grid == null or grid.mesh_library == null or cells.is_empty():
		mesh = null
		return

	# Where the leaves are measured from. A patch sits wherever it was dropped,
	# and the cells are the grid's — so everything is grown in the grid's space
	# and the node is put where the grid is.
	global_transform = grid.global_transform

	var grown: ArrayMesh = ArrayMesh.new()
	var wanted: VltFoliage.Settings = settings()

	for cell: Vector3i in cells:
		var item: int = grid.get_cell_item(cell)
		if item == GridMap.INVALID_CELL_ITEM:
			continue
		var source: Mesh = grid.mesh_library.get_item_mesh(item)
		if source == null:
			continue

		# The seed is the cell's own, so two cells of the same item are never the
		# same tree and a cell keeps its tree when its neighbours change.
		var sprigs: ArrayMesh = VltFoliage.leaves(source, _seed_of(cell), wanted)
		if sprigs.get_surface_count() == 0:
			continue

		# The grid's own placement: the cell's centre, the scale it draws its
		# palette at, **and the way the item was turned when it was painted**.
		#
		# That last one was missing, and it is the whole of why foliage could come
		# out crossways to the model it grew on. A cell stores an item and one of
		# twenty-four orientations; the mesh is sown in its own space, so leaves
		# placed against an identity basis stayed in the model's untouched pose
		# while the `GridMap` drew the model turned. On an unrotated cell the two
		# agree and nothing looks wrong — which is exactly why it survived every
		# render made here, none of which had turned anything.
		var placed: Transform3D = Transform3D(
			grid.get_cell_item_basis(cell).scaled(Vector3.ONE * grid.cell_scale),
			grid.map_to_local(cell)
		)
		_merge(grown, sprigs, placed)

	mesh = grown if grown.get_surface_count() > 0 else null


## A seed that depends on the cell and on this patch, and on nothing else. Two
## builds of the same map grow the same foliage; two patches over the same cell
## do not.
func _seed_of(cell: Vector3i) -> int:
	return hash(Vector4i(cell.x, cell.y, cell.z, seed))


## Adds `sprigs`, moved into place, to `into` — one surface per material so the
## colours stay apart.
static func _merge(into: ArrayMesh, sprigs: ArrayMesh, placed: Transform3D) -> void:
	for surface: int in range(sprigs.get_surface_count()):
		var arrays: Array = sprigs.surface_get_arrays(surface)
		@warning_ignore("unsafe_cast")
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
		@warning_ignore("unsafe_cast")
		var facing: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array

		var moved: PackedVector3Array = PackedVector3Array()
		moved.resize(points.size())
		for point: int in range(points.size()):
			moved[point] = placed * points[point]
		var turned: PackedVector3Array = PackedVector3Array()
		turned.resize(facing.size())
		for point: int in range(facing.size()):
			# The basis without the translation: a normal is a direction.
			turned[point] = (placed.basis * facing[point]).normalized()

		arrays[Mesh.ARRAY_VERTEX] = moved
		arrays[Mesh.ARRAY_NORMAL] = turned
		into.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		into.surface_set_material(
			into.get_surface_count() - 1, sprigs.surface_get_material(surface)
		)
