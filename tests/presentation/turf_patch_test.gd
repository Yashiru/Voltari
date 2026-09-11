extends GdUnitTestSuite

## Where the lawn refuses to grow.
##
## A patch clears a footprint around everything standing in it. These tests cover
## the free nodes beside the grid — the props that are not painted into a palette
## — because that is the path where the shape came out in the wrong place and
## nothing on screen said why: a bald rectangle on the map's origin with nothing
## standing in it, while the model itself grew grass through its feet.
##
## They reach for `_footprints` directly. What the patch actually produces is
## GPU particles, which no headless run can look at, and the footprints are the
## whole of the decision worth asserting.

## A square of ground big enough to hold a prop well away from its corner.
const SOWN: int = 15

## Where the prop's *mesh* is. Its node stays on the origin, which is the whole
## point: the two are not the same place, and only one of them is where the model
## is drawn.
const MESH_AT: Vector2 = Vector2(11.0, 11.0)


func _map() -> Node3D:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)

	var library: MeshLibrary = MeshLibrary.new()
	library.create_item(0)
	library.set_item_name(0, "slab")
	library.set_item_mesh(0, BoxMesh.new())

	var terrain: GridMap = GridMap.new()
	terrain.name = "Terrain"
	terrain.cell_size = Vector3.ONE
	# The cell's origin on the grid plane rather than half a cell above it, so the
	# floor is y 0 and every number below is the one an author reads off the map.
	terrain.cell_center_y = false
	terrain.mesh_library = library
	root.add_child(terrain)

	for x: int in range(SOWN):
		for z: int in range(SOWN):
			terrain.set_cell_item(Vector3i(x, 0, z), 0)
	return root


## The patch, sown over the whole floor. `layer` before `cells`: each is a setter
## that rebuilds, and the rebuild that counts is the one that has both.
func _patch(root: Node3D) -> TurfPatch:
	var patch: TurfPatch = TurfPatch.new()
	patch.name = "Turf"
	root.add_child(patch)
	patch.layer = patch.get_path_to(root.get_node("Terrain"))

	var sown: Array[Vector3i] = []
	for x: int in range(SOWN):
		for z: int in range(SOWN):
			sown.append(Vector3i(x, 0, z))
	patch.cells = sown
	return patch


## A model whose mesh is nowhere near the node holding it.
##
## Not a contrivance: it is every model in a finished asset pack, which carries
## the spot it stood on in the scene it was cut from — tens of metres — and it is
## what a foliage patch is by construction, since it bakes its leaves in the map's
## coordinates and leaves its own node at the origin.
##
## A plane rather than a box because `center_offset` is the only way to build a
## primitive away from its origin and `PlaneMesh` is the only one that has it.
## Lying flat, so the footprint it should clear has width in both x and z.
func _prop_whose_mesh_is_elsewhere(root: Node3D) -> void:
	var mesh: PlaneMesh = PlaneMesh.new()
	mesh.size = Vector2(2.0, 2.0)
	mesh.center_offset = Vector3(MESH_AT.x, 1.0, MESH_AT.y)

	var prop: MeshInstance3D = MeshInstance3D.new()
	prop.mesh = mesh
	# Above the floor, or the patch ignores it as ground rather than as a thing.
	prop.position = Vector3(0.0, 1.0, 0.0)
	root.add_child(prop)


func _footprints(patch: TurfPatch, terrain: GridMap) -> Array:
	var found: Array = patch.call("_footprints", terrain)
	return found


## Whether any footprint reaches over a spot on the ground.
func _cleared_at(stamps: Array, spot: Vector2) -> bool:
	for shape: PackedVector2Array in stamps:
		if shape.is_empty():
			continue
		var low: Vector2 = shape[0]
		var high: Vector2 = shape[0]
		for corner: Vector2 in shape:
			low = Vector2(minf(low.x, corner.x), minf(low.y, corner.y))
			high = Vector2(maxf(high.x, corner.x), maxf(high.y, corner.y))
		if low.x <= spot.x and high.x >= spot.x and low.y <= spot.y and high.y >= spot.y:
			return true
	return false


# --- a footprint belongs under the thing that casts it -------------------------


func test_a_prop_clears_the_ground_its_mesh_stands_on() -> void:
	var root: Node3D = _map()
	var terrain: GridMap = root.get_node("Terrain") as GridMap
	_prop_whose_mesh_is_elsewhere(root)
	var patch: TurfPatch = _patch(root)
	await get_tree().process_frame

	var stamps: Array = _footprints(patch, terrain)

	assert_bool(_cleared_at(stamps, MESH_AT)).override_failure_message(
		"nothing was cleared at %s, where the mesh is and where the model is drawn"
		% MESH_AT
	).is_true()


func test_a_prop_clears_nothing_where_only_its_node_is() -> void:
	# The defect, and it hid in the worst way: a rectangle the size of the model,
	# stamped on the map's origin, with nothing standing in it. The loop took the
	# *size* from the mesh's box and the *middle* from the node, so a box that was
	# not centred on its node was cleared in a place nobody had built anything.
	var root: Node3D = _map()
	var terrain: GridMap = root.get_node("Terrain") as GridMap
	_prop_whose_mesh_is_elsewhere(root)
	var patch: TurfPatch = _patch(root)
	await get_tree().process_frame

	var stamps: Array = _footprints(patch, terrain)

	assert_bool(_cleared_at(stamps, Vector2.ZERO)).override_failure_message(
		"the ground was cleared at the node's own position, where its mesh is not"
	).is_false()


# --- a patch is not an obstacle to a patch -------------------------------------


func test_foliage_beside_the_grid_is_not_cleared_around() -> void:
	# Turf does not have to make way for turf, and foliage is leaves sitting on
	# models whose own cells are cleared already — clearing a second time around
	# them eats exactly the lawn they were put there to stand in.
	#
	# The rule used to be "not me", which was right about one node and silent
	# about its neighbours.
	var root: Node3D = _map()
	var terrain: GridMap = root.get_node("Terrain") as GridMap
	var patch: TurfPatch = _patch(root)
	await get_tree().process_frame
	var alone: int = _footprints(patch, terrain).size()

	var leaves: VltFoliagePatch = VltFoliagePatch.new()
	# Given no cells, so it stays where it is put rather than moving onto the grid
	# — and well above the floor, where it would certainly be taken for a prop.
	leaves.position = Vector3(0.0, 2.0, 0.0)
	root.add_child(leaves)

	assert_int(_footprints(patch, terrain).size()).override_failure_message(
		"a foliage patch was cleared around as though it were something to avoid"
	).is_equal(alone)
