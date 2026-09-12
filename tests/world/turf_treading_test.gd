extends GdUnitTestSuite

## What the turf is told about somebody standing on it.
##
## A press is a position, an age and a width, and the only things that can go wrong
## are in the bookkeeping: a press that never expires, a slot that is never given
## back, a list the shader reads past the end of, or presses so close together that
## one walk fills every slot without covering any ground.
##
## The look itself is not testable here and is not pretended to be — whether a
## pressed lawn reads as a footstep is `tools/grass/` work, judged by rendering it.

const RADIUS: float = 0.3

## Far enough apart to be two presses, at that radius: the spacing threshold is
## 0.75 of it, so 0.3 clears it and 0.1 does not.
const APART: float = 0.3
const TOGETHER: float = 0.1


func _treading() -> TurfTreading:
	return TurfTreading.new()


static func _at(x: float, z: float) -> Vector3:
	return Vector3(x, 0.0, z)


# --- a press ------------------------------------------------------------------


func test_nobody_standing_means_nothing_is_pressed() -> void:
	var turf: TurfTreading = _treading()
	assert_int(turf.contact_count()).is_equal(0)
	assert_bool(turf.settling()).is_false()


func test_standing_presses_once_at_the_spot() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(4.0, 7.0), RADIUS)

	assert_int(turf.contact_count()).is_equal(1)
	var press: Vector4 = turf.contact_at(0)
	assert_float(press.x).is_equal_approx(4.0, 0.001)
	assert_float(press.y).is_equal_approx(7.0, 0.001)
	assert_float(press.z).is_equal_approx(0.0, 0.001)
	assert_float(press.w).is_equal_approx(RADIUS, 0.001)
	assert_bool(turf.settling()).is_true()


## The y of a world position is dropped on purpose: the field is flat and the
## shader compares on the ground plane. A press on a slope is a press.
func test_a_press_is_where_the_feet_are_on_the_ground() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, Vector3(2.0, 11.5, -3.0), RADIUS)

	var press: Vector4 = turf.contact_at(0)
	assert_float(press.x).is_equal_approx(2.0, 0.001)
	assert_float(press.y).is_equal_approx(-3.0, 0.001)


func test_the_width_is_whatever_pressed_it() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(0.0, 0.0), 1.25)

	assert_float(turf.contact_at(0).w).is_equal_approx(1.25, 0.001)


func test_a_press_that_makes_no_sense_is_refused() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(NAN, 0.0), RADIUS)
	turf.stand(1, _at(0.0, INF), RADIUS)
	turf.stand(2, _at(0.0, 0.0), 0.0)
	turf.stand(3, _at(0.0, 0.0), -1.0)

	assert_int(turf.contact_count()).is_equal(0)


# --- standing still versus walking --------------------------------------------


func test_standing_still_presses_once_and_not_once_a_frame() -> void:
	var turf: TurfTreading = _treading()
	for _frame: int in 60:
		turf.stand(0, _at(1.0, 1.0), RADIUS)

	assert_int(turf.contact_count()).is_equal(1)


func test_a_press_too_close_to_the_last_is_not_a_second_one() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(0.0, 0.0), RADIUS)
	turf.stand(0, _at(TOGETHER, 0.0), RADIUS)

	assert_int(turf.contact_count()).is_equal(1)


func test_walking_leaves_a_trail() -> void:
	var turf: TurfTreading = _treading()
	for step: int in 5:
		turf.stand(0, _at(float(step) * APART, 0.0), RADIUS)

	assert_int(turf.contact_count()).is_equal(5)
	# Oldest first, which is what lets expiry be a run at the front.
	assert_float(turf.contact_at(0).x).is_equal_approx(0.0, 0.001)
	assert_float(turf.contact_at(4).x).is_equal_approx(4.0 * APART, 0.001)


## The spacing is a share of the radius and not a distance, so somebody twice as
## wide leaves presses twice as far apart rather than twice as many.
func test_spacing_follows_the_radius_it_was_given() -> void:
	var turf: TurfTreading = _treading()
	var wide: float = RADIUS * 4.0
	turf.stand(0, _at(0.0, 0.0), wide)
	turf.stand(0, _at(APART, 0.0), wide)

	assert_int(turf.contact_count()).is_equal(1)


func test_two_actors_press_independently() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(0.0, 0.0), RADIUS)
	# Where the first one already stands. A second pair of feet is a second press,
	# whatever the first one did.
	turf.stand(1, _at(0.0, 0.0), RADIUS)

	assert_int(turf.contact_count()).is_equal(2)


func test_lifting_an_actor_lets_it_press_the_same_spot_again() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(0.0, 0.0), RADIUS)
	turf.stand(0, _at(0.0, 0.0), RADIUS)
	assert_int(turf.contact_count()).is_equal(1)

	turf.lift(0)
	turf.stand(0, _at(0.0, 0.0), RADIUS)
	assert_int(turf.contact_count()).is_equal(2)


# --- coming back up ------------------------------------------------------------


func test_a_press_ages() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(0.0, 0.0), RADIUS)
	turf.advance(0.25)

	assert_float(turf.contact_at(0).z).is_equal_approx(0.25, 0.001)


func test_a_recovered_press_gives_its_slot_back() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(0.0, 0.0), RADIUS)
	turf.advance(TurfTreading.RECOVER_SECONDS + 0.01)

	assert_int(turf.contact_count()).is_equal(0)
	assert_bool(turf.settling()).is_false()


func test_the_oldest_recovers_first_and_the_rest_keep_their_order() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(0.0, 0.0), RADIUS)
	turf.advance(TurfTreading.RECOVER_SECONDS * 0.8)
	turf.stand(0, _at(APART, 0.0), RADIUS)

	# Enough to finish the first and not the second.
	turf.advance(TurfTreading.RECOVER_SECONDS * 0.3)

	assert_int(turf.contact_count()).is_equal(1)
	assert_float(turf.contact_at(0).x).is_equal_approx(APART, 0.001)


func test_ages_never_climb_past_the_recovery() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(0.0, 0.0), RADIUS)
	for _frame: int in 600:
		turf.advance(0.5)

	# Not merely bounded: gone. A session running for an hour must not be handing
	# the shader a number it has to compare against anything.
	assert_int(turf.contact_count()).is_equal(0)


func test_a_frame_with_no_time_in_it_changes_nothing() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(0.0, 0.0), RADIUS)
	turf.advance(0.0)
	turf.advance(-1.0)

	assert_float(turf.contact_at(0).z).is_equal_approx(0.0, 0.001)
	assert_int(turf.contact_count()).is_equal(1)


# --- the ceiling ---------------------------------------------------------------


func test_the_list_never_grows_past_what_the_shader_can_read() -> void:
	var turf: TurfTreading = _treading()
	for step: int in TurfTreading.MOST_CONTACTS * 3:
		turf.stand(0, _at(float(step) * APART, 0.0), RADIUS)

	assert_int(turf.contact_count()).is_equal(TurfTreading.MOST_CONTACTS)


func test_the_ceiling_forgets_the_oldest_and_keeps_the_newest() -> void:
	var turf: TurfTreading = _treading()
	var steps: int = TurfTreading.MOST_CONTACTS + 4
	for step: int in steps:
		turf.stand(0, _at(float(step) * APART, 0.0), RADIUS)

	# The four earliest are gone; the most recent press is the last slot.
	assert_float(turf.contact_at(0).x).is_equal_approx(4.0 * APART, 0.001)
	assert_float(turf.contact_at(TurfTreading.MOST_CONTACTS - 1).x).is_equal_approx(
		float(steps - 1) * APART, 0.001
	)


func test_a_slot_past_the_live_ones_reads_as_nothing() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(1.0, 1.0), RADIUS)

	assert_vector(turf.contact_at(1)).is_equal(Vector4.ZERO)
	assert_vector(turf.contact_at(-1)).is_equal(Vector4.ZERO)
	assert_vector(turf.contact_at(TurfTreading.MOST_CONTACTS)).is_equal(Vector4.ZERO)


# --- leaving ------------------------------------------------------------------


func test_quiet_leaves_nothing_pressed() -> void:
	var turf: TurfTreading = _treading()
	for step: int in 5:
		turf.stand(0, _at(float(step) * APART, 0.0), RADIUS)
	turf.quiet()

	assert_int(turf.contact_count()).is_equal(0)
	assert_bool(turf.settling()).is_false()


## A warp must not need a walk before the grass on the new map reacts.
func test_quiet_forgets_where_everybody_stood() -> void:
	var turf: TurfTreading = _treading()
	turf.stand(0, _at(0.0, 0.0), RADIUS)
	turf.quiet()
	turf.stand(0, _at(0.0, 0.0), RADIUS)

	assert_int(turf.contact_count()).is_equal(1)


# --- what the materials are told ----------------------------------------------


func _patch() -> TurfPatch:
	var patch: TurfPatch = TurfPatch.new()
	auto_free(patch)
	return patch


func test_a_patch_that_was_never_sown_has_no_material_to_write_to() -> void:
	var turf: TurfTreading = _treading()
	turf.of_patches([_patch()])

	assert_int(turf.material_count()).is_equal(0)


func test_a_null_patch_is_skipped_rather_than_crashing() -> void:
	var turf: TurfTreading = _treading()
	turf.of_patches([null])

	assert_int(turf.material_count()).is_equal(0)


## The whole point of `patches_under`: the map dock groups what it sows, so a patch
## is not promised to be a direct child of the map.
func test_patches_are_found_at_any_depth() -> void:
	var root: Node3D = Node3D.new()
	auto_free(root)
	var between: Node3D = Node3D.new()
	root.add_child(between)
	var patch: TurfPatch = TurfPatch.new()
	between.add_child(patch)

	var found: Array[TurfPatch] = TurfTreading.patches_under(root)
	assert_int(found.size()).is_equal(1)
	assert_object(found[0]).is_same(patch)


func test_nothing_under_nothing() -> void:
	assert_int(TurfTreading.patches_under(null).size()).is_equal(0)


## The uniforms the shader actually declares, written to a real material carrying
## the real shader. What this catches is the two files disagreeing about a name or
## a type — which no test of the bookkeeping above can see.
func test_the_shader_takes_what_is_written_to_it() -> void:
	var shader: Shader = ResourceLoader.load(TurfPatch.SCATTER_SHADER, "Shader") as Shader
	assert_object(shader).is_not_null()

	var declared: Array[String] = []
	for one: Dictionary in shader.get_shader_uniform_list(true):
		var name: String = one["name"]
		declared.append(name)

	assert_array(declared).contains([
		TurfTreading.CONTACTS,
		TurfTreading.COUNT,
		TurfTreading.SECONDS,
		TurfTreading.STRENGTH,
	])

	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = shader
	var turf: TurfTreading = _treading()
	turf.of_patches([])
	turf.stand(0, _at(1.0, 2.0), RADIUS)

	# Written straight rather than through a patch, because a patch needs a sown
	# `GridMap` to have a material at all and this is about the uniforms.
	material.set_shader_parameter(TurfTreading.CONTACTS, _list_of(turf))
	material.set_shader_parameter(TurfTreading.COUNT, turf.contact_count())

	var back: PackedVector4Array = material.get_shader_parameter(TurfTreading.CONTACTS)
	assert_int(back.size()).is_equal(TurfTreading.MOST_CONTACTS)
	assert_float(back[0].x).is_equal_approx(1.0, 0.001)
	assert_int(material.get_shader_parameter(TurfTreading.COUNT)).is_equal(1)


## The list as the shader is handed it: the full fixed-size array, live presses
## packed against the front.
static func _list_of(turf: TurfTreading) -> PackedVector4Array:
	var list: PackedVector4Array = PackedVector4Array()
	list.resize(TurfTreading.MOST_CONTACTS)
	for index: int in turf.contact_count():
		list[index] = turf.contact_at(index)
	return list
