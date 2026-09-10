extends GdUnitTestSuite

## One creature on screen (spec 16, section 1).
##
## The load-bearing case is the missing model. Placeholder models live on one
## machine (decision 0027), so every clone has manifests naming scenes it has
## not got — and a battle that refused to draw would be a battle nobody else
## could run.

const MANIFESTS: String = "res://content/generated/presentation"
const FIXTURE: String = "res://tests/fixtures/models/clip_shapes.glb"


func _body() -> CreatureBody:
	var body: CreatureBody = auto_free(CreatureBody.new())
	add_child(body)
	return body


func _entry(scene: String, clips: Dictionary) -> PresentationEntry:
	return PresentationLoader.from_payload({
		"id": "test", "scene": scene, "height": 1.0, "clips": clips,
	})


func test_a_model_that_is_there_is_shown() -> void:
	var body: CreatureBody = _body()
	var found: bool = body.show_creature(
		_entry(FIXTURE, {"idle": ["ba10_waitA01", "ba10_waitB01"]})
	)

	assert_bool(found).override_failure_message(
		"a model that exists was not instanced"
	).is_true()
	assert_bool(body.has_model()).is_true()


func test_a_missing_model_shows_a_shape_rather_than_nothing() -> void:
	var body: CreatureBody = _body()
	var found: bool = body.show_creature(_entry("res://nowhere/at/all.tscn", {}))

	assert_bool(found).is_false()
	assert_bool(body.has_model()).is_false()
	assert_int(body.get_child_count()).override_failure_message(
		"a missing model left an empty seat"
	).is_greater(0)


func test_no_manifest_at_all_still_shows_something() -> void:
	# A species nobody has written a manifest for. Ordinary, not an error.
	var body: CreatureBody = _body()
	assert_bool(body.show_creature(null)).is_false()
	assert_int(body.get_child_count()).is_greater(0)


func test_showing_a_second_creature_replaces_the_first() -> void:
	# A switch and a capture both change who is standing there.
	var body: CreatureBody = _body()
	body.show_creature(_entry(FIXTURE, {"idle": ["ba10_waitA01"]}))
	body.show_creature(_entry("res://nowhere/at/all.tscn", {}))

	assert_bool(body.has_model()).override_failure_message(
		"the first creature was still standing there"
	).is_false()


func test_playing_a_slot_it_has_is_not_an_error() -> void:
	var body: CreatureBody = _body()
	body.show_creature(_entry(FIXTURE, {"idle": ["ba10_waitA01", "ba10_waitB01"]}))

	body.play("idle")
	body.play("faint")
	body.play("a_slot_nobody_declared")

	assert_bool(body.has_model()).is_true()


func test_a_stand_in_can_be_asked_to_move() -> void:
	# Silence is the ordinary answer, not a failure — and asking a shape to
	# animate must not stop a battle.
	var body: CreatureBody = _body()
	body.show_creature(_entry("res://nowhere/at/all.tscn", {"idle": ["x"]}))
	body.play("idle")

	assert_bool(body.has_model()).is_false()


# --- the manifests that ship -------------------------------------------------


func test_every_authored_manifest_shows_something() -> void:
	# Run over what is committed. On a clone the models are absent and every one
	# of these falls back, which is the case that has to work everywhere.
	var manifests: Dictionary[String, PresentationEntry] = (
		PresentationLoader.all_from_payload(VltContentPayloads.read_indexed(MANIFESTS))
	)
	assert_int(manifests.size()).is_greater(0)

	for id: String in manifests:
		var body: CreatureBody = _body()
		body.show_creature(manifests[id])
		assert_int(body.get_child_count()).override_failure_message(
			"\"%s\" produced an empty seat" % id
		).is_greater(0)


func test_every_slot_a_manifest_declares_is_in_the_vocabulary() -> void:
	# The manifests are generated from models, so a source clip mapping to a
	# slot nobody declared would arrive here rather than being noticed.
	var every: Array[String] = ClipMap.all_slots()
	var manifests: Dictionary[String, PresentationEntry] = (
		PresentationLoader.all_from_payload(VltContentPayloads.read_indexed(MANIFESTS))
	)

	for id: String in manifests:
		for slot: String in manifests[id].takes:
			assert_bool(every.has(slot)).override_failure_message(
				"\"%s\" declares \"%s\", which is in no set" % [id, slot]
			).is_true()
