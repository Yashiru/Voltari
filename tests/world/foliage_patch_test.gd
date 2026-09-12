extends GdUnitTestSuite

## Leaves on the cells somebody chose.
##
## The patch stores cells and numbers and grows the mesh again on load, which is
## only sound if two things hold. **A cell must keep its own tree**, or editing
## one corner of a map would reshuffle the foliage in another. And **a patch must
## own nothing but its leaves**, so deleting it cannot leave a hole where a model
## used to be.
##
## What it looks like is not asserted here and should not be.

const SEED: int = 77


func _library() -> MeshLibrary:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = Vector3(2.0, 2.0, 2.0)
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shape.surface_get_arrays(0))

	var library: MeshLibrary = MeshLibrary.new()
	library.create_item(0)
	library.set_item_name(0, "Box")
	library.set_item_mesh(0, mesh)
	return library


## A grid with `cells` filled, and a patch over them, both in the tree.
##
## `turned` is the orthogonal orientation every filled cell is painted with — 0 is
## the unrotated one a `GridMap` uses unless the author says otherwise.
func _patch(
	cells: Array[Vector3i], filled: Array[Vector3i], turned: int = 0
) -> VltFoliagePatch:
	var holder: Node3D = auto_free(Node3D.new())
	add_child(holder)

	var grid: GridMap = GridMap.new()
	grid.cell_size = Vector3.ONE
	grid.mesh_library = _library()
	holder.add_child(grid)
	for cell: Vector3i in filled:
		grid.set_cell_item(cell, 0, turned)

	var patch: VltFoliagePatch = VltFoliagePatch.new()
	patch.seed = SEED
	patch.density = 4.0
	holder.add_child(patch)
	patch.cells = cells
	patch.layer = patch.get_path_to(grid)
	return patch


## Where a patch hangs its sowings — one place per sown cell.
##
## **Not where each leaf is.** A patch draws a shared sowing once per cell now
## (decision 0079), and the per-instance buffer of a `MultiMesh` is held by the
## rendering server, which the headless run this suite requires does not have:
## `set_instance_transform` followed by `get_instance_transform` returns the
## identity, and `buffer` comes back empty.
##
## So the two halves are asserted where each is actually decided. Where a leaf
## sits on a model is `VltFoliage.scatter`, and `foliage_test.gd` holds it. Where
## a sowing is hung on the map is this, and it is the patch's whole job.
func _places(patch: VltFoliagePatch) -> Array[Transform3D]:
	var found: Array[Transform3D] = []
	for child: Node in patch.get_children():
		var shown: MultiMeshInstance3D = child as MultiMeshInstance3D
		if shown != null:
			found.append(shown.transform)
	return found


## Which sowings a patch is drawing, by identity. What makes "one per species and
## variant, not one per cell" checkable.
func _buffers(patch: VltFoliagePatch) -> Array[int]:
	var found: Array[int] = []
	for child: Node in patch.get_children():
		var shown: MultiMeshInstance3D = child as MultiMeshInstance3D
		if shown == null or shown.multimesh == null:
			continue
		var id: int = shown.multimesh.get_instance_id()
		if not found.has(id):
			found.append(id)
	return found


## Whether a patch is drawing anything at all.
func _grew(patch: VltFoliagePatch) -> bool:
	return patch.leaf_total() > 0


# --- a cell keeps its own tree -----------------------------------------------


func test_the_same_cells_grow_the_same_leaves() -> void:
	var cells: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(3, 0, 1)]
	var once: VltFoliagePatch = _patch(cells, cells)
	var again: VltFoliagePatch = _patch(cells, cells)

	assert_int(again.leaf_total()).is_equal(once.leaf_total())
	var first: Array[Transform3D] = _places(once)
	var second: Array[Transform3D] = _places(again)
	assert_int(second.size()).is_equal(first.size())
	for place: int in range(first.size()):
		assert_bool(second[place].is_equal_approx(first[place])).is_true()


func test_a_species_is_sown_a_few_times_and_shared() -> void:
	# **The trade decision 0079 made.** A sowing used to be built per cell, which
	# cost 6.8 MB a tree and put a hundred surfaces on one patch. Cells draw from
	# a handful of sowings now, so the memory follows the palette rather than the
	# map — and two cells that draw the same one are identical, which is the price
	# and is stated here rather than discovered.
	var cells: Array[Vector3i] = []
	for x: int in range(12):
		cells.append(Vector3i(x, 0, 0))
	var patch: VltFoliagePatch = _patch(cells, cells)

	assert_int(_places(patch).size()).override_failure_message(
		"a sowing is hung once per sown cell"
	).is_equal(12)
	assert_int(_buffers(patch).size()).override_failure_message(
		"twelve cells drew more sowings than the species has variants"
	).is_less_equal(3)


func test_one_variant_is_one_sowing_however_many_cells() -> void:
	# The memory claim, made checkable: what is held does not grow with the map.
	var few: Array[Vector3i] = [Vector3i(0, 0, 0)]
	var many: Array[Vector3i] = []
	for x: int in range(20):
		many.append(Vector3i(x, 0, 0))

	var one: VltFoliagePatch = _patch(few, few)
	one.variants = 1
	var lots: VltFoliagePatch = _patch(many, many)
	lots.variants = 1

	assert_int(_buffers(lots).size()).is_equal(1)
	assert_int(lots.buffer_total()).override_failure_message(
		"twenty cells held twenty times the leaves of one"
	).is_equal(one.buffer_total())
	# And it is still drawn everywhere it was sown.
	assert_int(lots.leaf_total()).is_equal(one.leaf_total() * 20)


func test_a_cell_keeps_its_own_tree_when_its_neighbours_change() -> void:
	# What survived the move to shared sowings, and the reason editing one corner
	# of a map does not reshuffle another.
	var alone: Array[Vector3i] = [Vector3i(4, 0, 4)]
	var crowded: Array[Vector3i] = [Vector3i(4, 0, 4), Vector3i(5, 0, 4), Vector3i(6, 0, 4)]
	var one: VltFoliagePatch = _patch(alone, alone)
	var among: VltFoliagePatch = _patch(crowded, crowded)

	assert_int(among.variant_of(Vector3i(4, 0, 4))).is_equal(one.variant_of(Vector3i(4, 0, 4)))


func test_rerolling_the_patch_changes_which_tree_a_cell_draws() -> void:
	# Over enough cells a reroll has to land somewhere. Asked of the variant
	# rather than of the leaves: where a leaf sits is `VltFoliage`'s and is held
	# by `foliage_test.gd`, and the buffer it lands in cannot be read back
	# headlessly.
	var cells: Array[Vector3i] = []
	for x: int in range(16):
		cells.append(Vector3i(x, 0, 0))
	var patch: VltFoliagePatch = _patch(cells, cells)

	var before: Array[int] = []
	for cell: Vector3i in cells:
		before.append(patch.variant_of(cell))

	patch.seed = SEED + 1

	var moved: int = 0
	for index: int in range(cells.size()):
		if patch.variant_of(cells[index]) != before[index]:
			moved += 1
	assert_int(moved).override_failure_message(
		"the seed was changed and every cell drew the same tree as before"
	).is_greater(0)


# --- it owns nothing but its leaves ------------------------------------------


func test_a_patch_over_empty_cells_grows_nothing() -> void:
	var patch: VltFoliagePatch = _patch([Vector3i(4, 0, 4)], [])
	assert_bool(_grew(patch)).is_false()
	assert_int(patch.leaf_total()).is_equal(0)


func test_a_patch_with_no_cells_grows_nothing() -> void:
	var patch: VltFoliagePatch = _patch([], [Vector3i(0, 0, 0)])
	assert_bool(_grew(patch)).is_false()


func test_a_sowing_is_hung_over_the_cell_it_was_sown_on() -> void:
	var cells: Array[Vector3i] = [Vector3i(5, 0, 2)]
	var patch: VltFoliagePatch = _patch(cells, cells)
	var places: Array[Transform3D] = _places(patch)

	assert_int(places.size()).is_equal(1)
	var grid: GridMap = patch.get_node(patch.layer) as GridMap
	assert_vector(places[0].origin).is_equal_approx(
		grid.map_to_local(Vector3i(5, 0, 2)), Vector3.ONE * 0.001
	)


# --- the settings belong to the patch ----------------------------------------


func test_turning_the_density_up_grows_more_leaves() -> void:
	var cells: Array[Vector3i] = [Vector3i(0, 0, 0)]
	var patch: VltFoliagePatch = _patch(cells, cells)
	var before: int = patch.leaf_total()

	patch.density = patch.density * 3.0
	assert_int(patch.leaf_total()).is_greater(before)


# --- a turned cell grows turned leaves ---------------------------------------


func test_a_sowing_follows_a_cell_that_was_painted_turned() -> void:
	# The defect this exists for: a cell stores an item *and* one of twenty-four
	# orientations. Hung against an identity basis, the leaves stay in the model's
	# untouched pose while the `GridMap` draws the model turned — foliage
	# crossways to the thing it grew on. On an unrotated cell the two agree, which
	# is why every render made here missed it.
	var cells: Array[Vector3i] = [Vector3i(0, 0, 0)]
	var upright: VltFoliagePatch = _patch(cells, cells)
	# 16 is a quarter turn about Y in Godot's orthogonal table.
	var sideways: VltFoliagePatch = _patch(cells, cells, 16)

	var straight: Array[Transform3D] = _places(upright)
	var turned: Array[Transform3D] = _places(sideways)
	assert_int(turned.size()).is_equal(straight.size())
	assert_int(straight.size()).is_greater(0)

	# Asked of the grid rather than written out: which way orientation 16 turns is
	# the engine's convention, and a test that guesses it is testing the guess.
	var grid: GridMap = sideways.get_node(sideways.layer) as GridMap
	var quarter: Basis = grid.get_basis_with_orthogonal_index(16)

	assert_bool(turned[0].basis.is_equal_approx(straight[0].basis)).override_failure_message(
		"turning the cell changed nothing, so its orientation is being ignored"
	).is_false()
	assert_bool(
		turned[0].basis.is_equal_approx(quarter.scaled(Vector3.ONE * grid.cell_scale))
	).override_failure_message(
		"the sowing was turned by something other than the cell's own orientation"
	).is_true()


# --- the leaves are never written into the scene ------------------------------


func test_saving_the_scene_does_not_carry_the_leaves_into_it() -> void:
	# The leaves are derived from the cells and the numbers beside them, and are
	# grown again on load — so a copy in the `.tscn` is one nobody reads. It is
	# also not small: four cells of this came to 45 MB of base64 inside one map,
	# and every world built afterwards paid six seconds to parse it.
	var patch: VltFoliagePatch = _patch([Vector3i(0, 0, 0)], [Vector3i(0, 0, 0)])
	assert_bool(_grew(patch)).override_failure_message(
		"the fixture grew nothing, so this test cannot say anything"
	).is_true()

	patch.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)

	assert_bool(_grew(patch)).override_failure_message(
		"the leaves were still on the node when the scene was packed"
	).is_false()


func test_the_leaves_come_back_once_the_scene_is_written() -> void:
	# Dropping it for the save is only acceptable if the editor still shows it
	# afterwards. A patch that went blank every time somebody pressed Ctrl+S would
	# be traded one problem for a worse one.
	var patch: VltFoliagePatch = _patch([Vector3i(0, 0, 0)], [Vector3i(0, 0, 0)])
	var before: int = patch.leaf_total()

	patch.notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
	patch.notification(Node.NOTIFICATION_EDITOR_POST_SAVE)

	assert_bool(_grew(patch)).is_true()
	assert_int(patch.leaf_total()).override_failure_message(
		"the leaves came back different, so they are not purely derived"
	).is_equal(before)
