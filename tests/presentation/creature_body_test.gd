extends GdUnitTestSuite

## One creature on screen (spec 16, section 1).
##
## The load-bearing case is the missing model. Species models live on one
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


# --- never still --------------------------------------------------------------


func test_a_creature_starts_breathing_the_moment_it_is_shown() -> void:
	# A creature only ever plays its entry clip on a switch, so waiting for one
	# left whoever opened the battle standing in a rest pose until it was hit.
	var body: CreatureBody = _body()
	body.show_creature(_entry(FIXTURE, {"idle": ["ba10_waitA01"]}))

	assert_bool(body.is_animating()).override_failure_message(
		"nothing was playing after the creature was put on stage"
	).is_true()


func test_a_clip_hands_back_to_the_idle() -> void:
	# The whole of the "plays once then freezes" complaint. Driven by the signal
	# the player emits rather than by waiting out the clip, so the test does not
	# depend on how long an animation is.
	var body: CreatureBody = _body()
	body.show_creature(_entry(FIXTURE, {
		"idle": ["ba10_waitA01"], "attack_physical": ["ba20_buturi01"],
	}))

	body.play("attack_physical")
	assert_str(body.playing()).is_equal("ba20_buturi01")

	body.finished_playing()
	assert_str(body.playing()).override_failure_message(
		"a finished clip left the creature frozen"
	).is_equal("ba10_waitA01")


func test_the_idle_hands_back_to_itself() -> void:
	# What loops it, without anything here knowing that a loop is what it is.
	var body: CreatureBody = _body()
	body.show_creature(_entry(FIXTURE, {"idle": ["ba10_waitA01"]}))

	body.finished_playing()
	assert_str(body.playing()).is_equal("ba10_waitA01")


func test_a_second_idle_take_is_reached_sometimes_and_not_always() -> void:
	# Every repeat would make a creature twitchy; never would make the extra
	# takes decoration nobody sees (decision 0055).
	var body: CreatureBody = _body()
	body.show_creature(
		_entry(FIXTURE, {"idle": ["ba10_waitA01", "ba10_waitB01"]})
	)

	var seen: Dictionary[String, int] = {}
	for repeat: int in range(400):
		body.finished_playing()
		var take: String = body.playing()
		seen[take] = seen.get(take, 0) + 1

	assert_int(seen.get("ba10_waitA01", 0)).override_failure_message(
		"the first take never played"
	).is_greater(0)
	assert_int(seen.get("ba10_waitB01", 0)).override_failure_message(
		"the second take never played, so a creature with two idles has one"
	).is_greater(0)
	assert_bool(
		seen.get("ba10_waitA01", 0) > seen.get("ba10_waitB01", 0) * 4
	).override_failure_message(
		"the variant was not the exception: %s" % seen
	).is_true()


func test_the_variant_never_runs_twice_in_a_row() -> void:
	# The whole of the complaint, and the reason a coin flip was not enough. A
	# one-in-four variant comes up twice in a row six times in a hundred, and
	# twice in a row is not "occasionally" — it is what a viewer reads as the
	# loop having changed.
	var body: CreatureBody = _body()
	body.show_creature(
		_entry(FIXTURE, {"idle": ["ba10_waitA01", "ba10_waitB01"]})
	)

	var previous: String = ""
	for repeat: int in range(600):
		body.finished_playing()
		var take: String = body.playing()
		assert_bool(take == "ba10_waitB01" and previous == "ba10_waitB01").override_failure_message(
			"the variant played twice running, at repeat %d" % repeat
		).is_false()
		previous = take


func test_plain_repeats_separate_two_variants() -> void:
	# Not merely "not adjacent": a floor of plain repeats is what makes the first
	# take the idle by construction rather than on average.
	var body: CreatureBody = _body()
	body.show_creature(
		_entry(FIXTURE, {"idle": ["ba10_waitA01", "ba10_waitB01"]})
	)

	var gap: int = 0
	var shortest: int = 1 << 20
	var variants: int = 0
	for repeat: int in range(1200):
		body.finished_playing()
		if body.playing() == "ba10_waitB01":
			if variants > 0:
				shortest = mini(shortest, gap)
			variants += 1
			gap = 0
			continue
		gap += 1

	assert_int(variants).override_failure_message("the variant never played").is_greater(1)
	assert_int(shortest).override_failure_message(
		"two variants were only %d plain repeats apart" % shortest
	).is_greater_equal(CreatureBody.PLAIN_BETWEEN_VARIANTS)


func test_a_creature_with_one_idle_take_never_varies() -> void:
	var body: CreatureBody = _body()
	body.show_creature(_entry(FIXTURE, {"idle": ["ba10_waitA01"]}))

	for repeat: int in range(50):
		body.finished_playing()
		assert_str(body.playing()).is_equal("ba10_waitA01")


func test_a_stand_in_is_asked_for_nothing_and_does_not_break() -> void:
	# No model, no player, no signal. The idle must be a no-op rather than a
	# crash, because half the machines running this have no models at all.
	var body: CreatureBody = _body()
	body.show_creature(_entry("res://nowhere/at/all.tscn", {"idle": ["ba10_waitA01"]}))

	body.finished_playing()
	assert_float(body.play("attack_physical")).is_equal(0.0)
	assert_bool(body.is_animating()).is_false()


# --- how long a clip runs -----------------------------------------------------


func test_playing_a_clip_reports_how_long_it_takes() -> void:
	# The caller's pacing. A fixed wait runs the next thing over the top of a
	# long attack and leaves a gap after a short one, and that gap is what makes
	# a hit look late.
	var body: CreatureBody = _body()
	body.show_creature(_entry(FIXTURE, {"idle": ["ba10_waitA01"]}))

	assert_float(body.play("idle")).override_failure_message(
		"a clip that plays reported no length"
	).is_greater(0.0)


func test_a_slot_this_creature_has_not_got_reports_nothing() -> void:
	var body: CreatureBody = _body()
	body.show_creature(_entry(FIXTURE, {"idle": ["ba10_waitA01"]}))

	assert_float(body.play("faint")).is_equal(0.0)


# --- the size the manifest asks for -------------------------------------------


func test_a_model_is_scaled_to_the_height_it_declares() -> void:
	# The field was loaded, documented and read by nobody. A creature drawn at
	# whatever its exporter produced — half a metre against a metre and a half —
	# makes framing a battle impossible.
	var body: CreatureBody = _body()
	var entry: PresentationEntry = _entry(FIXTURE, {"idle": ["ba10_waitA01"]})
	entry.height = 3.0
	body.show_creature(entry)

	assert_float(body.shown_height()).override_failure_message(
		"the model kept its own height instead of the one the manifest asks for"
	).is_equal_approx(3.0, 0.01)


func test_two_creatures_of_different_sizes_end_up_the_same_height() -> void:
	# The point of the field: a battle is framed once, not per species.
	var body: CreatureBody = _body()
	var entry: PresentationEntry = _entry(FIXTURE, {"idle": ["ba10_waitA01"]})
	entry.height = 1.0
	body.show_creature(entry)

	var other: CreatureBody = _body()
	var taller: PresentationEntry = _entry(FIXTURE, {"idle": ["ba10_waitA01"]})
	taller.height = 1.0
	other.show_creature(taller)

	assert_float(body.shown_height()).is_equal_approx(other.shown_height(), 0.01)
