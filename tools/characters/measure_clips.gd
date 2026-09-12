extends SceneTree

## Measures the character's clips on the character's own rig.
##
##   godot --headless --path . --script tools/characters/measure_clips.gd
##
## Every number in `WalkerGait` comes from here, and this exists so they can be
## checked rather than believed. It replaced `measure_gaits.gd`, which asked a
## different and weaker question — see below.
##
## ## Why the speed is read off the foot and not off the cadence
##
## An in-place clip is a clip with the root's travel subtracted, so the foot that
## is planted on the ground moves **backwards, relative to the body, at exactly
## the ground speed**. That is a direct reading with nothing assumed in it: find
## the frames where a toe is at its lowest, and measure how fast it slides.
##
## The tool this replaced could not do that, because it ran before the clips were
## retargeted: it read the cadence — how often a foot lands, which is honest —
## and then multiplied by a step length taken as a fixed fraction of the
## character's height. That fraction is anthropometry, and this character is not
## anthropometric: 1.70 m tall with 0.64 m legs and a head a third of its height.
## The estimate came out 10% fast for the run and 14% fast for the walk, which is
## a foot that slides forwards for no reason anybody could have found in the code.
##
## ## What else it prints, and what for
##
## - **The lowest a toe reaches**, in metres above the floor. Not measured against
##   the rest, which stopped being the pose the mesh was modelled in the day the
##   silhouette fixer straightened the legs: what says the retarget is sound is
##   that every clip agrees with every other one to within a few centimetres. One
##   clip on stilts among ten that are not is the failure this catches.
## - **Net yaw.** How far a turn clip actually turns. They were ordered as 90 and
##   180 and they are not, and a turn that is played without knowing that ends
##   the move pointing somewhere nobody asked for.
## - **Root travel.** What a clip moves the body by. Zero for everything the
##   overworld plays; not zero for the stairs and the throw, which is why those
##   two cannot simply be played in place.

const MODEL: String = "res://game/assets/characters/main-char.glb"

## Enough to resolve a contact to about a hundredth of a cycle on the shortest
## clip, which is 0.6 s.
const SAMPLES: int = 90

## How close to its lowest a toe has to be to count as planted.
##
## Two centimetres: under the roll of a foot pushing off, over the noise of a
## clip that was keyframed at thirty a second and resampled.
const PLANTED: float = 0.02


func _init() -> void:
	var model: Node = (load(MODEL) as PackedScene).instantiate()
	get_root().add_child(model)
	await process_frame

	var skeleton: Skeleton3D = _first(model, "Skeleton3D") as Skeleton3D
	var player: AnimationPlayer = AnimationPlayer.new()
	model.add_child(player)
	# The clips address `%GeneralSkeleton`, and a unique name resolves from the
	# instanced scene's root — so the player has to be rooted at the model rather
	# than at itself.
	player.root_node = NodePath("..")
	player.add_animation_library("clips", HumanoidClips.library())

	var toes: Array[int] = [
		skeleton.find_bone("mixamorig_LeftToe_End"), skeleton.find_bone("mixamorig_RightToe_End")
	]
	print("model   %s" % MODEL)
	print("bones   %d\n" % skeleton.get_bone_count())
	print(
		"%-16s %7s %5s %6s | %8s | %9s | %8s | %s"
		% ["clip", "length", "loop", "tracks", "toe low", "speed", "net yaw", "root travel"]
	)

	for slot: String in HumanoidClips.EVERY:
		if not player.has_animation("clips/%s" % slot):
			print("%-16s absent" % slot)
			continue
		await _report(player, skeleton, toes, slot)

	model.queue_free()
	quit()


func _report(
	player: AnimationPlayer, skeleton: Skeleton3D, toes: Array[int], slot: String
) -> void:
	var clip: Animation = player.get_animation("clips/%s" % slot)
	var hips: int = skeleton.find_bone("Hips")

	# Measured with the loop off, on a copy. A looping clip blends its tail back
	# towards its first frame, and a sample taken inside that blend reads a stair
	# climb as going nowhere and a gait as reversing. The loop mode itself is
	# reported from the real clip, above.
	var measuring: String = "measuring/%s" % slot
	var flat: Animation = clip.duplicate(true)
	flat.loop_mode = Animation.LOOP_NONE
	var bench: AnimationLibrary = AnimationLibrary.new()
	bench.add_animation(slot, flat)
	if player.has_animation_library("measuring"):
		player.remove_animation_library("measuring")
	player.add_animation_library("measuring", bench)

	var height: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	var reach: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
	var root: Array[Vector3] = []
	var yaw: PackedFloat32Array = PackedFloat32Array()

	player.play(measuring)
	for sample: int in range(SAMPLES + 1):
		player.seek(flat.length * float(sample) / float(SAMPLES), true)
		await process_frame
		for side: int in range(2):
			var at: Vector3 = skeleton.get_bone_global_pose(toes[side]).origin
			height[side].append(at.y)
			reach[side].append(at.z)
		var pose: Transform3D = skeleton.get_bone_global_pose(hips)
		root.append(pose.origin)
		yaw.append(atan2(pose.basis.z.x, pose.basis.z.z))

	var step: float = clip.length / float(SAMPLES)
	var lowest: float = minf(_least(height[0]), _least(height[1]))
	var speeds: Array[float] = []
	for side: int in range(2):
		var measured: float = _planted_speed(height[side], reach[side], step)
		if measured > 0.0:
			speeds.append(measured)

	print(
		(
			"%-16s %6.3fs %5s %6d | %+7.3f m | %8s | %+7.1f° | %+.3f m fwd %+.3f m up"
			% [
				slot,
				clip.length,
				"yes" if clip.loop_mode != Animation.LOOP_NONE else "no",
				clip.get_track_count(),
				lowest,
				_speeds(speeds),
				rad_to_deg(_turned(yaw)),
				root[root.size() - 1].z - root[0].z,
				root[root.size() - 1].y - root[0].y,
			]
		)
	)


## How fast the ground goes past, read off whichever foot is on it.
##
## Zero when no foot is planted long enough to measure, which is the honest
## answer for a clip that is not a gait.
func _planted_speed(height: PackedFloat32Array, reach: PackedFloat32Array, step: float) -> float:
	var floor_at: float = _least(height) + PLANTED
	var samples: Array[float] = []
	for index: int in range(height.size() - 1):
		if height[index] <= floor_at and height[index + 1] <= floor_at:
			samples.append(-(reach[index + 1] - reach[index]) / step)

	if samples.is_empty():
		return 0.0
	samples.sort()
	# The median rather than the mean: the first and last frame of a contact are
	# a foot arriving and a foot leaving, and both are slower than the ground.
	return samples[samples.size() / 2]


## How far the body turned in total, following the short way round each step so a
## turn past a half circle is not read as a turn back.
func _turned(yaw: PackedFloat32Array) -> float:
	var total: float = 0.0
	for index: int in range(1, yaw.size()):
		total += angle_difference(yaw[index - 1], yaw[index])
	return total


func _least(values: PackedFloat32Array) -> float:
	var lowest: float = INF
	for value: float in values:
		lowest = minf(lowest, value)
	return lowest


func _speeds(measured: Array[float]) -> String:
	if measured.is_empty():
		return "       —"
	if measured.size() == 1:
		return "%7.2f " % measured[0]
	# Both feet, because one foot agreeing with itself proves nothing.
	return "%.2f/%.2f" % [measured[0], measured[1]]


func _first(node: Node, of_class: String) -> Node:
	if node.get_class() == of_class:
		return node
	for child: Node in node.get_children():
		var deeper: Node = _first(child, of_class)
		if deeper != null:
			return deeper
	return null
