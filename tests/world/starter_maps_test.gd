extends GdUnitTestSuite

## The maps that actually ship, put through the validator (spec 14, section 7;
## spec 15, section 7).
##
## Every other world test runs on fixtures built in code. This one is the other
## end: it opens what is committed, and it is the only test that would notice a
## door painted to nowhere.
##
## It is also what the validator was written for. Until now it had only maps
## built to fail.

const FIELD: String = "res://game/maps/starter_field.tscn"
const CAVE: String = "res://game/maps/starter_cave.tscn"
const ENTRY: String = "starter_field"
const ENCOUNTERS: String = "res://content/generated/encounters"


func _maps() -> Array[VltWorldMap]:
	var loaded: Array[VltWorldMap] = []
	for path: String in [FIELD, CAVE]:
		var packed: PackedScene = load(path)
		assert_object(packed).override_failure_message("no map at %s" % path).is_not_null()
		loaded.append(auto_free(packed.instantiate() as VltWorldMap))
	return loaded


func _tables() -> PackedStringArray:
	return VltContentPayloads.ids_in(ENCOUNTERS)


func test_the_starter_maps_pass_every_check() -> void:
	# Warps that lead somewhere standable, zones that name a table the build
	# produced, lines that exist, flags read by something that sets them, and
	# nothing unreachable from where a new game begins.
	var problems: PackedStringArray = VltMapValidator.check(
		_maps(), _tables(), ENTRY, VltTranslationTable.all_keys()
	)

	assert_array(problems).override_failure_message(
		"the committed maps do not validate:\n  %s" % "\n  ".join(problems)
	).is_empty()


func test_they_survived_being_packed() -> void:
	# The trap in generating a scene rather than painting one: a node whose
	# owner is not the scene root is dropped on save, and the file comes back
	# looking fine and holding nothing.
	var maps: Array[VltWorldMap] = _maps()

	for map: VltWorldMap in maps:
		assert_object(map.terrain).override_failure_message(
			"map \"%s\" lost its terrain layer" % map.map_id
		).is_not_null()
		assert_object(map.decor).override_failure_message(
			"map \"%s\" lost its decoration layer, so there is nowhere to paint one"
			% map.map_id
		).is_not_null()
		assert_bool(map.is_walkable(Vector2i(1, 1))).override_failure_message(
			"map \"%s\" has no cells at all" % map.map_id
		).is_true()

	assert_int(maps[0].warps().size()).is_greater(0)
	assert_int(maps[0].zones().size()).is_greater(0)
	assert_int(maps[0].events().size()).is_greater(0)


func test_the_door_leads_both_ways() -> void:
	# A one-way door is the classic painted mistake, and the validator does not
	# catch it: leaving somewhere is legitimate.
	var maps: Array[VltWorldMap] = _maps()
	var field: VltWorldMap = maps[0]
	var cave: VltWorldMap = maps[1]

	var out: VltWarp = field.warps()[0]
	assert_str(out.to_map).is_equal(cave.map_id)

	var back: VltWarp = cave.warps()[0]
	assert_str(back.to_map).is_equal(field.map_id)
	assert_bool(cave.is_walkable(out.to_cell)).is_true()
	assert_bool(field.is_walkable(back.to_cell)).is_true()


func test_the_flag_crosses_the_map() -> void:
	# The reason there are two maps rather than one. A quest that begins in one
	# room and pays off in another is the normal case, and the flag check is
	# global for exactly that.
	var maps: Array[VltWorldMap] = _maps()

	var set_anywhere: bool = false
	var read_anywhere: bool = false
	for map: VltWorldMap in maps:
		for event: VltEvent in map.events():
			for step: VltEventStep in VltMapValidator.steps_in(event):
				var writes: VltSetFlagStep = step as VltSetFlagStep
				if writes != null and writes.flag == "read_the_sign":
					set_anywhere = true
				var reads: VltBranchStep = step as VltBranchStep
				if reads != null and reads.flag == "read_the_sign":
					read_anywhere = true

	assert_bool(set_anywhere).is_true()
	assert_bool(read_anywhere).is_true()


func test_the_grid_is_the_one_new_maps_use() -> void:
	# Two places that both know how wide a cell is are two places that disagree
	# the first time one changes. The starter maps read it from the same constant
	# the New map button does.
	for map: VltWorldMap in _maps():
		for layer: GridMap in [map.terrain, map.blocking, map.decor]:
			assert_float(layer.cell_size.x).override_failure_message(
				"%s/%s is on a %.2f m grid" % [map.map_id, layer.name, layer.cell_size.x]
			).is_equal_approx(VltNewMap.CELL_SIZE, 0.001)
			assert_float(layer.cell_scale).override_failure_message(
				"%s/%s draws its tiles at %.2f" % [map.map_id, layer.name, layer.cell_scale]
			).is_equal_approx(VltNewMap.ART_SCALE, 0.001)


func test_a_tile_fills_its_cell() -> void:
	# The two numbers answer two questions and have to agree: the library is
	# authored at two metres a tile, so on a one-metre grid it is drawn at half.
	# Get that wrong and every tile overlaps its neighbours four times over.
	var library: MeshLibrary = load("res://game/maps/tiles.meshlib") as MeshLibrary
	var ground: float = library.get_item_mesh(0).get_aabb().size.x

	assert_float(ground * VltNewMap.ART_SCALE).override_failure_message(
		"a %.2f m tile drawn at %.2f does not fill a %.2f m cell"
		% [ground, VltNewMap.ART_SCALE, VltNewMap.CELL_SIZE]
	).is_equal_approx(VltNewMap.CELL_SIZE, 0.01)
