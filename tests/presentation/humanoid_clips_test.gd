extends GdUnitTestSuite

## The character's animation vocabulary and the files behind it (decision 0074).
##
## Every clip is a separate asset now, so the two things that used to be
## impossible to get wrong are the two things to pin: that the vocabulary and the
## folder still agree, and that a clip's loop mode is the one its slot calls for.
##
## Both are import-time facts, which is exactly why they are asserted here. A
## `.import` file is edited by a dialog and reviewed as a diff of quoted keys;
## nothing else in the repository would notice a clip that quietly stopped
## looping until somebody watched the character stop dead mid-stride.

const FOLDER: String = HumanoidClips.SOURCE_FOLDER


func test_every_slot_has_a_file() -> void:
	for slot: String in HumanoidClips.EVERY:
		assert_bool(ResourceLoader.exists(HumanoidClips.source_of(slot))).override_failure_message(
			"the vocabulary names %s and there is no %s.fbx" % [slot, slot]
		).is_true()


func test_every_file_is_in_the_vocabulary() -> void:
	# The other way round, and the one that actually catches something: a clip
	# dropped into the folder and never named here is an asset nobody can play,
	# committed and forgotten.
	for file: String in DirAccess.get_files_at(FOLDER):
		if not file.ends_with(".fbx"):
			continue
		var slot: String = file.trim_suffix(".fbx")
		assert_bool(HumanoidClips.EVERY.has(slot)).override_failure_message(
			"%s is in the folder and in no slot" % file
		).is_true()


func test_every_file_imports_as_a_library_carrying_one_take() -> void:
	# Imported as an `AnimationLibrary` rather than as a scene: there is no mesh
	# in any of them, and a second skeleton per clip is eleven skeletons nobody
	# asked for.
	for slot: String in HumanoidClips.EVERY:
		var source: Resource = ResourceLoader.load(HumanoidClips.source_of(slot))
		assert_object(source).override_failure_message(
			"%s did not import" % slot
		).is_instanceof(AnimationLibrary)
		assert_bool((source as AnimationLibrary).has_animation(HumanoidClips.TAKE)).override_failure_message(
			"%s carries no %s take" % [slot, HumanoidClips.TAKE]
		).is_true()


func test_the_library_carries_every_slot_under_its_own_name() -> void:
	var clips: AnimationLibrary = HumanoidClips.library()

	for slot: String in HumanoidClips.EVERY:
		assert_bool(clips.has_animation(slot)).override_failure_message(
			"the library has no %s" % slot
		).is_true()


func test_a_slot_loops_exactly_when_it_should() -> void:
	# Set in the `.import`, not by the runtime patching a shared resource on every
	# load (decision 0057). This is where the two lists are held to each other.
	var clips: AnimationLibrary = HumanoidClips.library()

	for slot: String in HumanoidClips.EVERY:
		var loops: bool = clips.get_animation(slot).loop_mode != Animation.LOOP_NONE
		assert_bool(loops).override_failure_message(
			"%s %s and the vocabulary says it should %s"
			% [slot, "loops" if loops else "does not loop", "" if HumanoidClips.loops(slot) else "not"]
		).is_equal(HumanoidClips.loops(slot))


func test_the_clips_address_the_skeleton_the_model_carries() -> void:
	# The retarget is what makes this true: both the model and the clips are
	# imported through the same bone map, so a clip names `%GeneralSkeleton` and
	# lands on any character imported the same way. Without it the tracks address
	# a node that is not there and the character stands in its rest pose, silently.
	var clips: AnimationLibrary = HumanoidClips.library()
	var clip: Animation = clips.get_animation(HumanoidClips.IDLE)

	assert_int(clip.get_track_count()).is_greater(0)
	for track: int in range(clip.get_track_count()):
		assert_str(String(clip.track_get_path(track))).override_failure_message(
			"a track addresses %s rather than the profile skeleton" % clip.track_get_path(track)
		).starts_with("%GeneralSkeleton:")


func test_the_model_answers_to_that_name() -> void:
	var model: Node = (load(WalkerBody.MODEL) as PackedScene).instantiate()
	auto_free(model)

	assert_bool(model.has_node("%GeneralSkeleton")).override_failure_message(
		"the model's skeleton is not the profile's — was it imported without the bone map?"
	).is_true()


func test_the_arms_stay_on_their_own_side_of_the_body() -> void:
	# The retarget got this wrong and nothing caught it: the upper arm landed
	# correctly and the forearm swung inwards, so the hand came out of the middle
	# of the chest, thirty centimetres from where the model's own clips put it.
	# The silhouette fixer is what corrects it, and this is what says it stayed
	# corrected — for the three clips the player is looking at all the time.
	var model: Node = (load(WalkerBody.MODEL) as PackedScene).instantiate()
	auto_free(model)
	add_child(model)
	var skeleton: Skeleton3D = model.get_node("%GeneralSkeleton") as Skeleton3D
	var player: AnimationPlayer = AnimationPlayer.new()
	model.add_child(player)
	player.root_node = NodePath("..")
	player.add_animation_library("clips", HumanoidClips.library())

	var chest: int = skeleton.find_bone("Chest")
	var sides: Dictionary[String, float] = {"LeftHand": 1.0, "RightHand": -1.0}

	for slot: String in [HumanoidClips.IDLE, HumanoidClips.WALK, HumanoidClips.RUN]:
		var clip: Animation = player.get_animation("clips/%s" % slot)
		player.play("clips/%s" % slot)
		for sample: int in range(6):
			player.seek(clip.length * float(sample) / 6.0, true)
			for hand: String in sides:
				var apart: float = (
					skeleton.get_bone_global_pose(skeleton.find_bone(hand)).origin.x
					- skeleton.get_bone_global_pose(chest).origin.x
				)
				assert_float(apart * sides[hand]).override_failure_message(
					"in %s the %s is %.3f m the wrong side of the chest"
					% [slot, hand, -apart * sides[hand]]
				).is_greater(0.05)
