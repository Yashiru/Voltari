extends GdUnitTestSuite

## A model placed as a node, and what it stops (spec 14, section 2).
##
## The questions that run through all of this are decision 0072's, asked of a
## thing that carries its own rotation and scale instead of one of twenty-four
## turns: is the shape where the mesh is, is the error always on the side of
## *more* solid, and does anything you can plainly walk under stay walkable.

const REACH: float = VltFootprint.REACH

## Well clear of anything: used to check that somewhere is open rather than that
## a boundary falls exactly here.
const AWAY: Vector2 = Vector2(9.0, 9.0)


# --- the simple case ----------------------------------------------------------


func test_a_prop_stops_you_where_it_stands() -> void:
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))

	assert_bool(map.blocked_at(_flat(prop.position), 0.0)).is_true()
	assert_bool(map.blocked_at(AWAY, 0.0)).is_false()


func test_a_prop_stops_you_where_its_mesh_is_and_no_further() -> void:
	# A metre across, so the cell around it stays walkable. This is the whole
	# point of measuring a mesh instead of claiming a cell.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))
	var middle: Vector2 = _flat(prop.position)

	assert_bool(map.blocked_at(middle + Vector2(0.4, 0.0), 0.0)).is_true()
	assert_bool(map.blocked_at(middle + Vector2(0.7, 0.0), 0.0)).is_false()


func test_a_prop_that_does_not_block_stops_nobody() -> void:
	# A flower, a rug, a sign painted on the ground. Said once, on the prop.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))
	prop.blocks = false
	map.forget_shapes()

	assert_array(map.footprints()).is_empty()


func test_a_prop_with_no_mesh_stops_nobody() -> void:
	var map: VltWorldMap = _map()
	var prop: VltProp = VltProp.new()
	map.add_child(prop)
	map.forget_shapes()

	assert_array(map.footprints()).is_empty()


func test_a_hidden_prop_stops_nobody() -> void:
	# An author hiding a prop to look behind it would otherwise still walk into
	# it, which is the kind of thing that gets blamed on the map.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))
	prop.visible = false
	map.forget_shapes()

	assert_array(map.footprints()).is_empty()


func test_a_prop_whose_model_is_hidden_stops_nobody() -> void:
	# The same, one level down: hiding the mesh rather than the prop.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))
	(prop.get_child(0) as MeshInstance3D).visible = false
	map.forget_shapes()

	assert_array(map.footprints()).is_empty()


# --- what a cell could not say ------------------------------------------------


func test_a_turned_prop_blocks_the_way_it_is_turned() -> void:
	# Two metres one way and forty centimetres the other. Turned a quarter, the
	# long side is the other side — and reading the mesh without the turn would
	# give a clearance at right angles to the thing it is for.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(2.0, 3.0, 0.4))
	var middle: Vector2 = _flat(prop.position)

	assert_bool(map.blocked_at(middle + Vector2(0.8, 0.0), 0.0)).is_true()
	assert_bool(map.blocked_at(middle + Vector2(0.0, 0.8), 0.0)).is_false()

	prop.rotation = Vector3(0.0, PI * 0.5, 0.0)
	map.forget_shapes()

	assert_bool(map.blocked_at(middle + Vector2(0.8, 0.0), 0.0)).is_false()
	assert_bool(map.blocked_at(middle + Vector2(0.0, 0.8), 0.0)).is_true()


func test_a_scaled_prop_blocks_the_size_it_is_drawn() -> void:
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 1.0, 1.0))
	var middle: Vector2 = _flat(prop.position)

	assert_bool(map.blocked_at(middle + Vector2(0.8, 0.0), 0.0)).is_false()

	prop.scale = Vector3(2.0, 1.0, 2.0)
	map.forget_shapes()

	assert_bool(map.blocked_at(middle + Vector2(0.8, 0.0), 0.0)).is_true()


func test_a_prop_scaled_on_one_axis_only_grows_that_way() -> void:
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 1.0, 1.0))
	var middle: Vector2 = _flat(prop.position)

	prop.scale = Vector3(3.0, 1.0, 1.0)
	map.forget_shapes()

	assert_bool(map.blocked_at(middle + Vector2(1.2, 0.0), 0.0)).is_true()
	assert_bool(map.blocked_at(middle + Vector2(0.0, 1.2), 0.0)).is_false()


func test_a_mirrored_prop_blocks_where_it_is_drawn() -> void:
	# The model sits a metre to one side inside the prop. Mirrored, it is drawn a
	# metre to the other side, and that is where it has to stop you — a shape
	# derived from the mesh's own numbers rather than from where it is drawn
	# would block the empty side.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))
	var middle: Vector2 = _flat(prop.position)
	(prop.get_child(0) as Node3D).position = Vector3(1.0, 0.0, 0.0)
	prop.scale = Vector3(-1.0, 1.0, 1.0)
	map.forget_shapes()

	assert_bool(map.blocked_at(middle + Vector2(-1.0, 0.0), 0.0)).is_true()
	assert_bool(map.blocked_at(middle + Vector2(1.0, 0.0), 0.0)).is_false()


func test_a_prop_flattened_to_nothing_stops_nobody() -> void:
	# A scale of zero is a typo, not a shape. It must not throw and must not
	# leave a sliver of a polygon behind for the walker to catch on.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))
	prop.scale = Vector3.ZERO
	map.forget_shapes()

	assert_array(map.footprints()).is_empty()


# --- the height band ----------------------------------------------------------


func test_a_prop_raised_out_of_the_way_takes_no_ground() -> void:
	# A balcony, an eave, a canopy. The band is a height in the map's space, not
	# a distance above the prop, which is the only way this can be said.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 1.0, 1.0))
	prop.position += Vector3(0.0, REACH + 0.5, 0.0)
	map.forget_shapes()

	assert_array(map.footprints()).is_empty()


func test_a_prop_taller_than_the_band_still_blocks_its_base() -> void:
	# Cut at the band rather than kept or dropped whole: a tree is mostly above
	# it and its trunk is not.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 12.0, 1.0))

	assert_bool(map.blocked_at(_flat(prop.position), 0.0)).is_true()


func test_a_prop_lifted_part_way_still_blocks_what_reaches_down() -> void:
	# Half in the band and half above it. The half in the band is what stops you.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))
	prop.position += Vector3(0.0, REACH - 0.5, 0.0)
	map.forget_shapes()

	assert_bool(map.blocked_at(_flat(prop.position), 0.0)).is_true()


# --- several models in one prop -----------------------------------------------


func test_two_models_in_one_prop_are_two_shapes() -> void:
	# The gazebo lesson, which cost a revert once: one hull around four posts
	# fills the gazebo in and stops anybody walking under it.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(0.4, 3.0, 0.4))
	_add_model(prop, Vector3(2.0, 0.0, 0.0), Vector3(0.4, 3.0, 0.4))
	map.forget_shapes()

	var middle: Vector2 = _flat(prop.position)
	assert_int(map.footprints().size()).is_equal(2)
	assert_bool(map.blocked_at(middle, 0.0)).is_true()
	assert_bool(map.blocked_at(middle + Vector2(2.0, 0.0), 0.0)).is_true()
	# And the gap between them is a gap.
	assert_bool(map.blocked_at(middle + Vector2(1.0, 0.0), 0.0)).is_false()


func test_a_prop_inside_a_prop_is_measured_once() -> void:
	# The outer prop's shape is built from every mesh below it, so descending
	# into the inner one would hand the walker two copies of the same wall.
	var map: VltWorldMap = _map()
	var outer: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))
	var inner: VltProp = VltProp.new()
	outer.add_child(inner)
	map.forget_shapes()

	assert_int(map.props().size()).is_equal(1)
	assert_int(map.footprints().size()).is_equal(1)
	assert_array(VltProp.nested_under(map)).contains([inner])


# --- living on a map ----------------------------------------------------------


func test_a_prop_makes_its_cell_unstandable() -> void:
	var map: VltWorldMap = _map()
	_prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))

	assert_bool(map.is_walkable(Vector2i(2, 2))).is_false()
	assert_bool(map.is_walkable(Vector2i(4, 4))).is_true()


func test_a_prop_leaves_the_cell_itself_alone() -> void:
	# A shape is not a claim on a cell: the cell still exists and is still open,
	# which is what lets you stand in the part of it the prop does not fill.
	var map: VltWorldMap = _map()
	_prop(map, Vector2i(2, 2), Vector3(0.2, 3.0, 0.2))

	assert_bool(map.is_open(Vector2i(2, 2))).is_true()


func test_a_prop_blocks_on_a_map_that_speaks_in_whole_cells() -> void:
	# The palette switch is about how a *painted* layer is read. A prop is a node
	# type that did not exist before, so nothing already painted changes because
	# of it and it has no older reading to be gated by.
	var map: VltWorldMap = _map()
	assert_array(VltFootprint.on(map.blocking)).is_empty()

	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))
	assert_bool(map.blocked_at(_flat(prop.position), 0.0)).is_true()


func test_a_prop_pushes_back_out_of_itself() -> void:
	# What makes a wall something you slide along rather than stop dead against.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))
	var middle: Vector2 = _flat(prop.position)

	# Outside the shape and close enough for the disc to touch it, which is where
	# a walker meets a wall. Half a metre across, so 0.6 is clear of the edge and
	# a radius of 0.2 reaches it.
	var normal: Vector2 = map.surface_at(middle + Vector2(0.6, 0.0), 0.2)
	assert_float(normal.length()).is_equal_approx(1.0, 0.001)
	assert_float(normal.x).is_greater(0.5)


func test_moving_a_prop_moves_what_stops_you() -> void:
	# Derived, never stored: there is no copy of the shape to go stale, so this
	# cannot be got wrong by forgetting to update something.
	var map: VltWorldMap = _map()
	var prop: VltProp = _prop(map, Vector2i(2, 2), Vector3(1.0, 3.0, 1.0))
	var was: Vector2 = _flat(prop.position)

	prop.position = map.centre_of(Vector2i(4, 4))
	map.forget_shapes()

	assert_bool(map.blocked_at(was, 0.0)).is_false()
	assert_bool(map.blocked_at(_flat(prop.position), 0.0)).is_true()


func test_a_painted_wall_and_a_prop_both_stop_you() -> void:
	# The two sources are one answer to the walker. Neither hides the other.
	var map: VltWorldMap = _map()
	map.remove_child(map.blocking)
	map.blocking.free()
	map.blocking = VltFixtureMap.shaped([Vector2i(1, 1)], Vector3(0.4, 3.0, 0.4))
	map.add_child(map.blocking)

	var prop: VltProp = _prop(map, Vector2i(4, 4), Vector3(1.0, 3.0, 1.0))

	assert_bool(map.blocked_at(_flat(map.centre_of(Vector2i(1, 1))), 0.1)).is_true()
	assert_bool(map.blocked_at(_flat(prop.position), 0.0)).is_true()


# --- fixtures -----------------------------------------------------------------


func _map() -> VltWorldMap:
	return auto_free(VltFixtureMap.map("field", VltFixtureMap.filled(Vector2i(6, 6))))


## A prop holding one box, standing on the centre of a cell.
func _prop(map: VltWorldMap, at: Vector2i, size: Vector3) -> VltProp:
	var prop: VltProp = VltProp.new()
	map.add_child(prop)
	prop.position = map.centre_of(at)
	_add_model(prop, Vector3.ZERO, size)
	map.forget_shapes()
	return prop


func _add_model(prop: VltProp, at: Vector3, size: Vector3) -> MeshInstance3D:
	var part: MeshInstance3D = MeshInstance3D.new()
	part.mesh = VltFixtureMap.block(size)
	prop.add_child(part)
	part.position = at
	return part


static func _flat(point: Vector3) -> Vector2:
	return Vector2(point.x, point.z)
