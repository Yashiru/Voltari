@tool
class_name VltFoliagePatch
extends Node3D

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
##
## ## Sown per species, drawn per tree (decision 0079)
##
## A sowing used to be built per cell and welded into one mesh. Measured, a
## single six-metre fir came to 169 872 triangles and 6.8 MB, and a hundred of
## them to a hundred surfaces and 680 MB — against a budget that guesses a
## million triangles for a flagship phone, for the whole scene.
##
## So the scatter is baked a few times per *species* and every tree of that
## species points at the same buffer. Memory stops following the number of trees
## and starts following the number of models in the palette.
##
## **One child node per sown cell**, each drawing the shared buffer at that
## cell's place. Not one batch for the whole patch, which would be fewer draw
## calls and would defeat the thing that matters more: a node the engine can see
## is off screen is a node it does not draw at all.

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

## How many different sowings a species gets, drawn from by cell.
##
## One would make every fir on the map identical leaf for leaf. A handful, with
## the free rotation the prop brush already gives each tree, makes the repetition
## very hard to catch — and the memory is this number times one sowing, whatever
## the map holds.
@export_range(1, 8, 1) var variants: int = 3:
	set(value):
		variants = value
		_regrow()

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
@export var colour: Color = Color(0.364, 0.7411, 0.082):
	set(value):
		colour = value
		_regrow()

@export_range(0.0, 1.0, 0.01) var colour_amount: float = 1.0:
	set(value):
		colour_amount = value
		_regrow()

## How much darker a leaf may come out than its branch, and across how many flat
## tones. What gives a sown blob its volume: every leaf sharing one fill reads as
## one mass, and a few tones apart lets the eye find the depth.
@export_range(0.0, 1.0, 0.01) var tone_spread: float = 0.22:
	set(value):
		tone_spread = value
		_regrow()

@export_range(1, 6, 1) var tone_steps: int = 3:
	set(value):
		tone_steps = value
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
@export_range(0.0, 60.0, 0.5) var sway: float = 1.0:
	set(value):
		sway = value
		_regrow()

@export_range(0.0, 0.6, 0.01) var stem_hold: float = 0.0:
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


## The grown mesh is never written into the scene.
##
## It is derived from the settings above and rebuilt in `_ready()`, so a copy in
## the `.tscn` is one nobody ever reads — and it is not a small one. Four cells of
## this in one map came to 45 MB of base64 inside the scene file. Nothing about
## that was visible: the map opened, the grass looked right, and the only symptom
## was that everything touching `game/maps/` had become slow.
##
## It was expensive in a place nobody would look for it. `WorldSandbox` opens every
## map in the folder to learn its id, and Godot's resource cache holds scenes
## weakly, so those 45 MB were re-parsed on every world built — six seconds each,
## and the test suite builds one per test. One scratch map took `world_sandbox_test`
## from 4.5 seconds to 272.
##
## Godot sends these two notifications around packing for exactly this purpose:
## drop what is derived, let the scene be written without it, put it back.
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_clear()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_regrow()


## How many leaves this patch is carrying. For a report, and for an author who
## wants to know what a density is costing before a profiler tells them.
func leaf_total() -> int:
	var total: int = 0
	for shown: MultiMeshInstance3D in _drawn():
		if shown.multimesh != null:
			total += shown.multimesh.instance_count
	return total


## How much the sowings themselves weigh, whatever the map draws them at. What
## makes "per species, not per tree" checkable rather than asserted.
func buffer_total() -> int:
	var seen: Dictionary[int, bool] = {}
	var total: int = 0
	for shown: MultiMeshInstance3D in _drawn():
		var spread: MultiMesh = shown.multimesh
		if spread == null or seen.has(spread.get_instance_id()):
			continue
		seen[spread.get_instance_id()] = true
		total += spread.instance_count
	return total


## The nodes this patch draws through.
func _drawn() -> Array[MultiMeshInstance3D]:
	var found: Array[MultiMeshInstance3D] = []
	for child: Node in get_children():
		var shown: MultiMeshInstance3D = child as MultiMeshInstance3D
		if shown != null:
			found.append(shown)
	return found


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
	wanted.tone_spread = tone_spread
	wanted.tone_steps = tone_steps
	wanted.variants = maxi(variants, 1)
	return wanted


## Grows the sowings a map needs and hangs one node over each sown cell.
##
## **A sowing per species and variant, not per cell.** The same fir drawn fifty
## times points at one buffer fifty times, which is the whole of decision 0079:
## memory follows the palette rather than the map.
func _regrow() -> void:
	if not is_inside_tree():
		return
	_clear()

	var grid: GridMap = get_node_or_null(layer) as GridMap
	if grid == null or grid.mesh_library == null or cells.is_empty():
		return

	# Where the leaves are measured from. A patch sits wherever it was dropped,
	# and the cells are the grid's — so everything is grown in the grid's space
	# and the node is put where the grid is.
	global_transform = grid.global_transform

	var wanted: VltFoliage.Settings = settings()
	var sown: Dictionary[String, Array] = {}

	for cell: Vector3i in cells:
		var item: int = grid.get_cell_item(cell)
		if item == GridMap.INVALID_CELL_ITEM:
			continue
		var source: Mesh = grid.mesh_library.get_item_mesh(item)
		if source == null:
			continue

		# Which of the species' sowings this cell drew. From the cell's own seed,
		# so a cell keeps its tree when its neighbours change.
		var pick: int = variant_of(cell)
		var key: String = "%d:%d" % [item, pick]
		if not sown.has(key):
			# Three numbers rather than two added together. `pick + seed` collides
			# whenever a reroll moves the pick down as the seed moves up, and a
			# reroll that quietly returns the same tree is the one thing this
			# setting exists to prevent.
			sown[key] = _variant(source, hash(Vector3i(item, pick, seed)), wanted)

		# The grid's own placement: the cell's centre, the scale it draws its
		# palette at, **and the way the item was turned when it was painted**.
		#
		# That last one was missing once, and it is the whole of why foliage could
		# come out crossways to the model it grew on.
		var placed: Transform3D = Transform3D(
			grid.get_cell_item_basis(cell).scaled(Vector3.ONE * grid.cell_scale),
			grid.map_to_local(cell)
		)

		for spread: Variant in sown[key]:
			var shown: MultiMeshInstance3D = MultiMeshInstance3D.new()
			@warning_ignore("unsafe_cast")
			shown.multimesh = spread as MultiMesh
			shown.transform = placed
			# Never given an owner: these are derived from the settings above and
			# rebuilt on load, so a copy in the `.tscn` is one nobody reads. That
			# mattered enough to be worth a comment of its own — see below.
			add_child(shown)


## One species' sowing, as instance buffers ready to be drawn anywhere.
##
## One buffer per surface that was sown, because the material is the surface's:
## a leaf is the colour of what it grew from.
func _variant(source: Mesh, from_seed: int, wanted: VltFoliage.Settings) -> Array:
	var made: Array = []
	var array_source: ArrayMesh = source as ArrayMesh
	if array_source == null:
		return made

	for sowing: VltFoliage.Sowing in VltFoliage.scatter(source, from_seed, wanted):
		# A card per material rather than one card and an override per node: the
		# card is six vertices, and carrying the material on it keeps every node
		# drawing this buffer identical.
		var leaf_card: ArrayMesh = VltFoliage.card()
		leaf_card.surface_set_material(
			0,
			VltFoliage.leaf_material(array_source.surface_get_material(sowing.surface), wanted)
		)
		made.append(VltFoliage.instances(sowing.leaves, leaf_card))

	return made


## Takes down what was drawn, so a regrow replaces rather than accumulates.
func _clear() -> void:
	for shown: MultiMeshInstance3D in _drawn():
		remove_child(shown)
		shown.queue_free()


## Which of the species' sowings a cell draws.
##
## From the cell's own seed, so a cell keeps its tree when its neighbours change
## — the property that survived the move to shared sowings, and the reason
## editing one corner of a map does not reshuffle another.
func variant_of(cell: Vector3i) -> int:
	return absi(_seed_of(cell)) % maxi(variants, 1)


## A seed that depends on the cell and on this patch, and on nothing else. Two
## builds of the same map grow the same foliage; two patches over the same cell
## do not.
func _seed_of(cell: Vector3i) -> int:
	return hash(Vector4i(cell.x, cell.y, cell.z, seed))
