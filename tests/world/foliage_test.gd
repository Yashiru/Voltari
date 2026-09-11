extends GdUnitTestSuite

## Sowing leaves over a mesh.
##
## Two properties carry this and neither is about how it looks. **It has to be
## repeatable**, because the sowing is baked into a library an author paints from
## — a rebuild that reshuffled the leaves would quietly redraw every map that used
## one. And **every leaf has to carry the normal of the surface under it**, which
## is the whole reason the thing works at all: give each leaf its own normal and a
## bush reads as a heap of independent flakes.
##
## What it looks like is not asserted anywhere and should not be. That is looked
## at, the way the grass is (decision 0059).

const SEED: int = 4242


func _settings(density: float = 40.0) -> VltFoliage.Settings:
	var settings: VltFoliage.Settings = VltFoliage.Settings.new()
	settings.density = density
	return settings


## A box, which has flat faces whose normals are known exactly — so a test can
## say what a leaf standing on one should be carrying.
func _box() -> ArrayMesh:
	var shape: BoxMesh = BoxMesh.new()
	shape.size = Vector3(2.0, 2.0, 2.0)
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, shape.surface_get_arrays(0))
	return mesh


func _leaf_surfaces(mesh: Mesh) -> Array[int]:
	# A sown mesh is the source's surfaces with one of leaves after each, so the
	# odd ones are the leaves.
	var found: Array[int] = []
	for surface: int in range(mesh.get_surface_count()):
		if surface % 2 == 1:
			found.append(surface)
	return found


# --- it has to be repeatable -------------------------------------------------


func test_the_same_seed_sows_the_same_leaves() -> void:
	var once: Mesh = VltFoliage.sown(_box(), SEED, _settings())
	var again: Mesh = VltFoliage.sown(_box(), SEED, _settings())

	assert_int(again.get_surface_count()).is_equal(once.get_surface_count())
	for surface: int in range(once.get_surface_count()):
		var first: PackedVector3Array = once.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		var second: PackedVector3Array = again.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		assert_int(second.size()).is_equal(first.size())
		for point: int in range(first.size()):
			assert_vector(second[point]).is_equal(first[point])


func test_a_different_seed_sows_different_leaves() -> void:
	var once: Mesh = VltFoliage.sown(_box(), SEED, _settings())
	var other: Mesh = VltFoliage.sown(_box(), SEED + 1, _settings())

	var first: PackedVector3Array = once.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	var second: PackedVector3Array = other.surface_get_arrays(1)[Mesh.ARRAY_VERTEX]
	assert_bool(first == second).override_failure_message(
		"two seeds produced the same sowing, so the seed is being ignored"
	).is_false()


# --- a leaf is shaded as the thing it grew on --------------------------------


func test_every_leaf_carries_the_normal_of_the_surface_under_it() -> void:
	var sown: Mesh = VltFoliage.sown(_box(), SEED, _settings())

	# A box's faces point exactly along the axes. Every leaf normal must be one of
	# those six and nothing in between: a leaf carrying its own normal would be
	# leaning, and leaning is what this rules out.
	var upright: int = 0
	for surface: int in _leaf_surfaces(sown):
		var normals: PackedVector3Array = sown.surface_get_arrays(surface)[Mesh.ARRAY_NORMAL]
		assert_int(normals.size()).is_greater(0)
		for normal: Vector3 in normals:
			var longest: float = maxf(absf(normal.x), maxf(absf(normal.y), absf(normal.z)))
			assert_float(longest).override_failure_message(
				"a leaf carries %s, which is not one of the box's face normals" % normal
			).is_equal_approx(1.0, 0.001)
			upright += 1
	assert_int(upright).is_greater(0)


func test_the_leaves_of_one_leaf_all_agree() -> void:
	var sown: Mesh = VltFoliage.sown(_box(), SEED, _settings())
	var normals: PackedVector3Array = sown.surface_get_arrays(1)[Mesh.ARRAY_NORMAL]

	# Six vertices to a leaf, and all six carry the surface's normal — not the
	# leaf's own, which would differ across its own fan.
	var leaf: int = 0
	while leaf + 5 < normals.size():
		for point: int in range(1, 6):
			assert_vector(normals[leaf + point]).is_equal(normals[leaf])
		leaf += 6


# --- what comes out ----------------------------------------------------------


func test_the_source_is_kept_and_the_leaves_are_added() -> void:
	var bare: ArrayMesh = _box()
	var sown: Mesh = VltFoliage.sown(bare, SEED, _settings())

	assert_int(sown.get_surface_count()).is_equal(bare.get_surface_count() * 2)
	var kept: PackedVector3Array = sown.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var source: PackedVector3Array = bare.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_int(kept.size()).is_equal(source.size())


func test_density_is_leaves_per_square_unit() -> void:
	# A two-unit box is twenty-four square units. Units of the mesh's own space,
	# not game metres: a GridMap draws an item at ART_SCALE.
	var settings: VltFoliage.Settings = _settings(10.0)
	assert_int(VltFoliage.leaf_count(_box(), settings)).is_equal(240)

	var sown: Mesh = VltFoliage.sown(_box(), SEED, settings)
	var normals: PackedVector3Array = sown.surface_get_arrays(1)[Mesh.ARRAY_NORMAL]
	assert_int(normals.size() / 6).is_equal(240)


func test_a_mesh_it_cannot_read_comes_back_untouched() -> void:
	var shape: BoxMesh = BoxMesh.new()
	assert_object(VltFoliage.sown(shape, SEED, _settings())).is_same(shape)


# --- only the surface that is the foliage ------------------------------------


func test_a_surface_far_smaller_than_the_largest_is_left_bare() -> void:
	# A big face and a sliver, as a palm is a canopy and a trunk. Sowing both is
	# what put brown leaves on the trunk, so the sliver has to come back bare.
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad(4.0))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad(0.5))

	var sown: Mesh = VltFoliage.sown(mesh, SEED, _settings())
	# The big face keeps its own surface and gains one; the sliver only keeps its.
	assert_int(sown.get_surface_count()).is_equal(3)


func test_the_threshold_can_be_turned_off() -> void:
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad(4.0))
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _quad(0.5))

	var settings: VltFoliage.Settings = _settings()
	settings.dominant_share = 0.0
	assert_int(VltFoliage.sown(mesh, SEED, settings).get_surface_count()).is_equal(4)


## A flat square of `side`, facing up.
func _quad(side: float) -> Array:
	var half: float = side * 0.5
	var made: Array = []
	made.resize(Mesh.ARRAY_MAX)
	made[Mesh.ARRAY_VERTEX] = PackedVector3Array([
		Vector3(-half, 0.0, -half), Vector3(half, 0.0, -half),
		Vector3(half, 0.0, half), Vector3(-half, 0.0, half),
	])
	made[Mesh.ARRAY_NORMAL] = PackedVector3Array([
		Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP,
	])
	made[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 0, 3, 2])
	return made


# --- the leaves can be given a colour ----------------------------------------


## A box wearing a material of the kind the tile library writes.
func _painted(branch: Color) -> ArrayMesh:
	var mesh: ArrayMesh = _box()
	var dressed: ShaderMaterial = ShaderMaterial.new()
	dressed.shader = ResourceLoader.load(
		"res://game/presentation/creature/comic.gdshader", "Shader") as Shader
	dressed.set_shader_parameter("albedo", branch)
	mesh.surface_set_material(0, dressed)
	return mesh


func _leaf_albedo(mesh: Mesh) -> Color:
	var dressed: ShaderMaterial = mesh.surface_get_material(1) as ShaderMaterial
	@warning_ignore("unsafe_cast")
	var paint: Color = dressed.get_shader_parameter("albedo") as Color
	return paint


func test_leaves_keep_the_branch_colour_by_default() -> void:
	var branch: Color = Color(0.2, 0.5, 0.3)
	var sown: Mesh = VltFoliage.sown(_painted(branch), SEED, _settings())

	assert_object(_leaf_albedo(sown)).is_equal(branch)


func test_a_leaf_wears_the_moving_shader_and_the_branch_does_not() -> void:
	# A leaf flutters and the branch it grew on does not, so the two cannot share
	# a shader — but they do share every value on it, the colour included.
	var sown: Mesh = VltFoliage.sown(_painted(Color(0.2, 0.5, 0.3)), SEED, _settings())

	var branch: ShaderMaterial = sown.surface_get_material(0) as ShaderMaterial
	var leaf: ShaderMaterial = sown.surface_get_material(1) as ShaderMaterial
	assert_object(leaf).is_not_same(branch)
	assert_str(leaf.shader.resource_path).is_equal(VltFoliage.LEAF_SHADER)
	assert_bool(branch.shader.resource_path == VltFoliage.LEAF_SHADER).override_failure_message(
		"the branch was given the leaf's shader, so the model would flutter too"
	).is_false()


func test_leaves_take_the_colour_they_are_given() -> void:
	var branch: Color = Color(0.2, 0.5, 0.3)
	var settings: VltFoliage.Settings = _settings()
	settings.colour = Color(0.9, 0.1, 0.4)
	settings.colour_amount = 1.0

	# Channel by channel: a lerp to one does not come back bit-identical, and an
	# exact comparison fails on a difference too small to print.
	var sown: Mesh = VltFoliage.sown(_painted(branch), SEED, settings)
	var leaf: Color = _leaf_albedo(sown)
	assert_float(leaf.r).is_equal_approx(settings.colour.r, 0.001)
	assert_float(leaf.g).is_equal_approx(settings.colour.g, 0.001)
	assert_float(leaf.b).is_equal_approx(settings.colour.b, 0.001)
	# The branch is untouched: the material is shared with every other cell
	# drawing this item, so tinting it in place would repaint the tree too.
	@warning_ignore("unsafe_cast")
	var kept: Color = (sown.surface_get_material(0) as ShaderMaterial).get_shader_parameter(
		"albedo") as Color
	assert_object(kept).is_equal(branch)


func test_a_share_of_the_colour_lands_between_the_two() -> void:
	var branch: Color = Color(0.2, 0.5, 0.3)
	var settings: VltFoliage.Settings = _settings()
	settings.colour = Color(0.8, 0.5, 0.3)
	settings.colour_amount = 0.5

	var sown: Mesh = VltFoliage.sown(_painted(branch), SEED, settings)
	assert_float(_leaf_albedo(sown).r).is_equal_approx(0.5, 0.001)
