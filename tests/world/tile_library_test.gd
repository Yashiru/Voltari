extends GdUnitTestSuite

## A folder of models, turned into something you can paint with.
##
## Ids are what these tests are really about. A GridMap stores an id per cell, so
## an id that means "fence" today and "cactus" after a rebuild rewrites every
## painted map at once, silently — the sort of defect that is discovered months
## later and cannot be traced back.

const MODELS: String = "res://tests/fixtures/models"

## A palette with folders in it: one model at the root, one a folder down, one two
## folders down. Separate from `MODELS` so the tests that count items are not
## rewritten every time a category is added to this one.
const SORTED: String = "res://tests/fixtures/tiles"

const OUT: String = "user://tile_library_test.meshlib"

## A second output, used by the one test that cares what the resource *cache*
## holds. Its own path so nothing it leaves in the cache can reach another test.
const HELD: String = "user://tile_library_held_test.meshlib"


func before_test() -> void:
	_forget()


func after_test() -> void:
	_forget()


func _forget() -> void:
	for path: String in [OUT, HELD]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _build() -> VltTileLibrary.Report:
	return VltTileLibrary.build(MODELS, OUT)


func _library() -> MeshLibrary:
	return ResourceLoader.load(OUT, "MeshLibrary", ResourceLoader.CACHE_MODE_IGNORE) as MeshLibrary


# --- what one run produces ---------------------------------------------------


func test_a_folder_of_models_becomes_a_library() -> void:
	var report: VltTileLibrary.Report = _build()

	assert_bool(report.worked()).override_failure_message(
		"the build failed: %s" % ", ".join(report.problems)
	).is_true()
	assert_int(report.total()).is_greater(0)
	assert_object(_library()).is_not_null()


func test_every_item_is_named_after_its_file_and_carries_a_mesh() -> void:
	# The name is the only handle an author has in the palette, and an item with
	# no mesh is a cell that paints nothing.
	_build()
	var library: MeshLibrary = _library()

	for id: int in library.get_item_list():
		assert_str(library.get_item_name(id)).is_not_empty()
		assert_object(library.get_item_mesh(id)).override_failure_message(
			"item \"%s\" has no mesh" % library.get_item_name(id)
		).is_not_null()


func test_nothing_carries_a_collision_shape() -> void:
	# The overworld has no physics: what stops you is a painted layer (spec 14,
	# sections 1 and 3). A shape here would be a second answer to that question.
	_build()
	var library: MeshLibrary = _library()

	for id: int in library.get_item_list():
		assert_array(library.get_item_shapes(id)).override_failure_message(
			"item \"%s\" carries a shape, which is a second way to say what blocks"
			% library.get_item_name(id)
		).is_empty()


# --- ids do not move ---------------------------------------------------------


func test_building_twice_keeps_every_id() -> void:
	# The property the whole tool exists to preserve.
	_build()
	var before: Dictionary[String, int] = _ids_by_name(_library())

	var again: VltTileLibrary.Report = _build()
	var after: Dictionary[String, int] = _ids_by_name(_library())

	assert_int(again.added.size()).override_failure_message(
		"a second run created items that already existed"
	).is_equal(0)
	assert_int(again.kept.size()).is_equal(before.size())

	for item_name: String in before:
		assert_int(after.get(item_name, -1)).override_failure_message(
			"\"%s\" moved from id %d to %d" % [
				item_name, before[item_name], after.get(item_name, -1)
			]
		).is_equal(before[item_name])


## A library that already holds something, the way a real one does after the
## first run. Built by hand because one fixture model cannot stand in for a
## palette somebody has been adding to.
func _with_reserved(at: int, item_name: String) -> void:
	var library: MeshLibrary = MeshLibrary.new()
	library.create_item(at)
	library.set_item_name(at, item_name)
	library.set_item_mesh(at, BoxMesh.new())
	ResourceSaver.save(library, OUT)


func test_an_item_whose_model_is_gone_keeps_its_id() -> void:
	# Freeing the id would let the next model added take it, which is the
	# corruption this tool exists to prevent, with extra steps.
	_with_reserved(7, "a_model_that_left")

	var report: VltTileLibrary.Report = _build()
	var after: Dictionary[String, int] = _ids_by_name(_library())

	assert_int(after.get("a_model_that_left", -1)).override_failure_message(
		"an item lost its id when its model went away"
	).is_equal(7)
	assert_bool(report.orphaned.has("a_model_that_left")).override_failure_message(
		"the palette grew a tail and said nothing about it"
	).is_true()


func test_an_added_model_lands_past_the_highest_id() -> void:
	# One past the highest, never into a gap. Filling a gap is how an id comes to
	# mean something different from what a painted cell meant when it was
	# painted.
	_with_reserved(40, "reserved")

	_build()
	var after: Dictionary[String, int] = _ids_by_name(_library())

	assert_int(after.size()).is_equal(2)
	for item_name: String in after:
		if item_name == "reserved":
			continue
		assert_int(after[item_name]).override_failure_message(
			"\"%s\" was given id %d, which is below an id already in use"
			% [item_name, after[item_name]]
		).is_greater(40)


func _ids_by_name(library: MeshLibrary) -> Dictionary[String, int]:
	var by_name: Dictionary[String, int] = {}
	if library == null:
		return by_name
	for id: int in library.get_item_list():
		by_name[library.get_item_name(id)] = id
	return by_name


# --- folders are categories ---------------------------------------------------


func _sorted() -> VltTileLibrary.Report:
	return VltTileLibrary.build(SORTED, OUT)


func test_a_folder_under_the_root_becomes_part_of_the_name() -> void:
	# The whole of the category mechanism. The palette sorts and filters by name,
	# so a name that starts with a folder is a palette grouped by folder — there is
	# nothing else to it, and nothing else to keep in step.
	_sorted()
	var names: Dictionary[String, int] = _ids_by_name(_library())

	assert_bool(names.has("Plants/leaf")).override_failure_message(
		"expected an item named after its folder, got: %s" % ", ".join(names.keys())
	).is_true()


func test_a_category_inside_a_category_keeps_both() -> void:
	# Nothing in the rule stops at one folder, so nothing here does either.
	_sorted()
	var names: Dictionary[String, int] = _ids_by_name(_library())

	assert_bool(names.has("Ground/Paths/slab")).is_true()


func test_a_model_at_the_root_keeps_its_bare_name() -> void:
	# The property that lets a flat palette gain categories without any of its
	# existing items moving: a file that did not move is not renamed, so its id
	# does not move either, so no painted cell changes meaning.
	_sorted()
	var names: Dictionary[String, int] = _ids_by_name(_library())

	assert_bool(names.has("loose")).override_failure_message(
		"a root-level model was given a prefix, which would orphan every existing item"
	).is_true()


func test_the_report_counts_each_category() -> void:
	# The report is the only place an author can see that a folder was read as a
	# category. The root itself is the empty key.
	var report: VltTileLibrary.Report = _sorted()

	assert_int(report.categories.get("Plants", 0)).is_equal(1)
	assert_int(report.categories.get("Ground/Paths", 0)).is_equal(1)
	assert_int(report.categories.get("", 0)).is_equal(1)


func test_a_category_selects_surfaces_like_any_other_fragment() -> void:
	# Falls out of the name being a path: the layer fields match on the name, and
	# the name now carries its folders. Worth a test because it is the reason no
	# field had to learn what a category is.
	var report: VltTileLibrary.Report = VltTileLibrary.build(SORTED, OUT, "Plants/")

	assert_array(report.parting).contains(["Plants/leaf"])
	assert_array(report.parting).not_contains(["loose"])


# --- one copy of the library, not two ----------------------------------------


func test_a_build_fills_the_copy_everything_else_is_holding() -> void:
	# Two copies of one library is the whole defect. The tool wrote 303 items on
	# a copy of its own; the editor went on holding the 92 it had opened the scene
	# with; saving put those 92 back over the file. It was right for two hours and
	# then quietly was not.
	var first: MeshLibrary = MeshLibrary.new()
	first.create_item(0)
	first.set_item_name(0, "was_here_first")
	first.set_item_mesh(0, BoxMesh.new())
	ResourceSaver.save(first, HELD)

	# What an open scene's GridMap does: hold the library by its path.
	var held: MeshLibrary = ResourceLoader.load(HELD, "MeshLibrary") as MeshLibrary
	assert_int(held.get_item_list().size()).is_equal(1)

	VltTileLibrary.build(SORTED, HELD)

	assert_int(held.get_item_list().size()).override_failure_message(
		"the build went to a second copy — what everything else holds still has %d item(s),"
		% held.get_item_list().size()
		+ " so the palette would not show the rebuild and saving would undo it"
	).is_greater(1)


# --- a folder with nothing in it ---------------------------------------------


func test_an_empty_folder_is_a_problem() -> void:
	var report: VltTileLibrary.Report = VltTileLibrary.build("res://tests/fixtures/oracle", OUT)

	assert_bool(report.worked()).is_false()
	assert_str(report.problems[0]).contains("no models found")
