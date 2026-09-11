extends GdUnitTestSuite

## The presentation manifest, and the vocabulary two places have to agree on
## (spec 16, sections 4, 5 and 10).

const VOCABULARY: String = "res://content/generated/presentation/vocabulary.json"
const MANIFESTS: String = "res://content/generated/presentation"


func _payload(clips: Dictionary, extras: Array = [], stow: Array = []) -> Dictionary:
	return {
		"id": "species_base",
		"scene": "res://game/presentation/creature/example.tscn",
		"height": 1.2,
		"clips": clips,
		"extras": extras,
		"stow": stow,
	}


# --- the vocabulary lives in two places and must not drift -------------------


func test_the_build_and_the_runtime_agree_on_the_slots() -> void:
	# The slot list is written in the Node build and again in ClipMap. Two lists
	# that can drift, so the build emits its own and this compares them — neither
	# side can quietly win an argument the other does not know it is having.
	var emitted: Dictionary = VltContentPayloads.read_json(VOCABULARY)

	@warning_ignore("unsafe_cast")
	var sets: Dictionary = emitted["slots"] as Dictionary
	var from_build: PackedStringArray = PackedStringArray()
	for group: Variant in sets.keys():
		@warning_ignore("unsafe_cast")
		for slot: Variant in sets[group] as Array:
			@warning_ignore("unsafe_cast")
			from_build.append(slot as String)
	from_build.sort()

	var from_runtime: PackedStringArray = PackedStringArray(ClipMap.all_slots())
	from_runtime.sort()

	assert_array(from_runtime).override_failure_message(
		"the build knows %s and the runtime knows %s" % [from_build, from_runtime]
	).is_equal(from_build)


func test_every_slot_the_clip_map_can_produce_is_in_the_vocabulary() -> void:
	# A code mapping to a slot nobody declared would resolve at runtime and be
	# unaskable, which is the quiet half of the same drift.
	var every: Array[String] = ClipMap.all_slots()
	for code: String in ClipMap.BY_CODE:
		assert_bool(every.has(ClipMap.BY_CODE[code])).override_failure_message(
			"code \"%s\" maps to \"%s\", which is in no set" % [code, ClipMap.BY_CODE[code]]
		).is_true()
	for word: String in ClipMap.BARE:
		assert_bool(every.has(ClipMap.BARE[word])).is_true()


func test_every_code_declares_the_word_it_expects() -> void:
	# The two tables are read together on every lookup; a code in one and not the
	# other resolves to nothing at all.
	for code: String in ClipMap.BY_CODE:
		assert_bool(ClipMap.WORD_OF_CODE.has(code)).override_failure_message(
			"code \"%s\" has no expected word" % code
		).is_true()
	assert_int(ClipMap.WORD_OF_CODE.size()).is_equal(ClipMap.BY_CODE.size())


# --- loading -----------------------------------------------------------------


func test_a_manifest_round_trips_into_its_typed_form() -> void:
	var entry: PresentationEntry = PresentationLoader.from_payload(
		_payload({"idle": ["ba10_waitA01", "ba10_waitB01"], "faint": ["ba41_down01"]})
	)

	assert_str(entry.id).is_equal("species_base")
	assert_float(entry.height).is_equal_approx(1.2, 0.001)
	assert_array(entry.takes_for("idle")).is_equal(["ba10_waitA01", "ba10_waitB01"])
	assert_bool(entry.has("faint")).is_true()


func test_a_declared_fallback_resolves_to_the_slot_it_names() -> void:
	var entry: PresentationEntry = PresentationLoader.from_payload(
		_payload({"idle": ["ba10_waitA01"], "hurt": "use idle"})
	)

	assert_array(entry.takes_for("hurt")).is_equal(["ba10_waitA01"])
	assert_bool(entry.has("hurt")).is_true()


func test_a_fallback_stays_visible_rather_than_being_resolved_away() -> void:
	# "Still borrowing idle for hurt" has to be a question a reviewer can ask six
	# months later, which it is not if the load flattens it.
	var entry: PresentationEntry = PresentationLoader.from_payload(
		_payload({"idle": ["ba10_waitA01"], "hurt": "use idle"})
	)

	assert_bool(entry.takes.has("hurt")).is_false()
	assert_str(entry.fallbacks["hurt"]).is_equal("idle")


func test_a_slot_nobody_declared_has_nothing_rather_than_something() -> void:
	var entry: PresentationEntry = PresentationLoader.from_payload(
		_payload({"idle": ["ba10_waitA01"]})
	)

	assert_bool(entry.has("attack_physical")).is_false()
	assert_array(entry.takes_for("attack_physical")).is_empty()


func test_extras_and_stow_survive_the_load() -> void:
	var entry: PresentationEntry = PresentationLoader.from_payload(
		_payload({"idle": ["ba10_waitA01"]}, ["ba10_adjustear"], ["HideLeftEar"])
	)

	assert_array(entry.extras).is_equal(["ba10_adjustear"])
	assert_array(entry.stow).is_equal(["HideLeftEar"])


func test_every_clip_the_manifest_mentions_is_countable() -> void:
	# What turns "nothing is dropped" into something a meta-test can check
	# against the model once manifests exist.
	var entry: PresentationEntry = PresentationLoader.from_payload(
		_payload(
			{"idle": ["ba10_waitA01", "ba10_waitB01"], "faint": ["ba41_down01"]},
			["ba10_adjustear"],
			["HideLeftEar"]
		)
	)

	assert_int(entry.every_clip().size()).is_equal(5)


# --- what is authored today --------------------------------------------------


func test_a_manifest_built_from_a_real_model_loses_nothing() -> void:
	# The whole loop, on a file Godot's own glTF importer read: the model's clips
	# go through the resolver, into a manifest, back out typed — and the count has
	# to survive every step. Each stage is tested alone above; this is the one
	# that would notice a clip falling between two of them.
	var packed: PackedScene = load("res://tests/fixtures/models/clip_shapes.glb")
	var root: Node = auto_free(packed.instantiate())

	var player: AnimationPlayer = null
	for child: Node in root.get_children():
		if child is AnimationPlayer:
			player = child as AnimationPlayer

	var clips: PackedStringArray = player.get_animation_list()
	var mapping: ClipMap.Mapping = ClipMap.of(clips)

	# What a manifest generator will write, assembled here because no such tool
	# exists yet — the shape is the point, not who produces it.
	var by_slot: Dictionary = {}
	for slot: String in mapping.takes:
		by_slot[slot] = Array(mapping.takes[slot])
	var payload: Dictionary = {
		"id": "species_base",
		"scene": "res://tests/fixtures/models/clip_shapes.glb",
		"height": 0.4,
		"clips": by_slot,
		"extras": Array(mapping.extras),
		"stow": Array(mapping.stow),
	}

	var entry: PresentationEntry = PresentationLoader.from_payload(payload)
	var kept: PackedStringArray = entry.every_clip()

	# Effect tracks are the one thing a manifest does not carry as a clip: they
	# belong to the slot they accompany. Everything else must be here.
	var expected: int = clips.size()
	for slot: String in mapping.effects:
		expected -= mapping.effects[slot].size()

	assert_int(kept.size()).override_failure_message(
		"the model has %d clips and the manifest kept %d" % [clips.size(), kept.size()]
	).is_equal(expected)

	for name: String in kept:
		assert_bool(clips.has(name)).override_failure_message(
			"the manifest names \"%s\", which the model has not got" % name
		).is_true()


func test_every_authored_manifest_loads() -> void:
	# None are authored yet: a manifest naming a quarantined scene would name a
	# file CI cannot see (decision 0027), so they arrive with the fakemon. The
	# test is here so the day one lands, it is already covered.
	var manifests: Dictionary[String, PresentationEntry] = (
		PresentationLoader.all_from_payload(VltContentPayloads.read_indexed(MANIFESTS))
	)

	for id: String in VltContentPayloads.ids_in(MANIFESTS):
		assert_bool(manifests.has(id)).override_failure_message(
			"manifest \"%s\" is in the index but did not load" % id
		).is_true()
