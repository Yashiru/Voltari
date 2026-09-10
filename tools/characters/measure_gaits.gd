extends SceneTree

## Measures a character's gaits from the animation itself.
##
##   godot --headless --path . --script tools/characters/measure_gaits.gd
##
## The numbers in `WalkerGait` come from here, and this exists so they can be
## checked rather than believed. An in-place clip carries no root motion, so what
## can be read off it is the **cadence** — how often a foot lands — and the foot's
## travel relative to the body, which is a compressed stride and not a real one.
##
## Cadence is the honest one. Speed then follows from a step length, which for a
## human is a proportion of height: about 0.45 of it walking and 0.75 running.
## Those two ratios are the only numbers here that are not measured.

const MODEL: String = "res://game/assets/characters/main-char.glb"
const SAMPLES: int = 120

const WALK_STEP_PER_HEIGHT: float = 0.45
const RUN_STEP_PER_HEIGHT: float = 0.75

## Clips that are a gait, and whether they are a run.
const GAITS: Dictionary[String, bool] = {"Walking": false, "Running": true}


func _init() -> void:
	var root: Node = (load(MODEL) as PackedScene).instantiate()
	get_root().add_child(root)
	await process_frame

	var skeleton: Skeleton3D = _first(root, "Skeleton3D") as Skeleton3D
	var player: AnimationPlayer = _first(root, "AnimationPlayer") as AnimationPlayer
	var height: float = _height(root)

	print("model  %s" % MODEL)
	print("height %.3f m   bones %d" % [height, skeleton.get_bone_count()])
	print("forward %s (toes reach further than ankles along it)\n" % _forward(skeleton))

	for clip_name: String in GAITS:
		if not player.has_animation(clip_name):
			print("%-12s absent" % clip_name)
			continue
		await _report(player, skeleton, clip_name, height, GAITS[clip_name])

	root.queue_free()
	quit()


func _report(
	player: AnimationPlayer,
	skeleton: Skeleton3D,
	clip_name: String,
	height: float,
	running: bool
) -> void:
	var clip: Animation = player.get_animation(clip_name)
	var left: int = skeleton.find_bone("mixamorig_LeftFoot")
	var right: int = skeleton.find_bone("mixamorig_RightFoot")

	var lowest: float = 1e9
	var highest: float = -1e9
	player.play(clip_name)

	for sample: int in range(SAMPLES + 1):
		player.seek(clip.length * float(sample) / float(SAMPLES), true)
		await process_frame
		for bone: int in [left, right]:
			var at: float = skeleton.get_bone_global_pose(bone).origin.z
			lowest = minf(lowest, at)
			highest = maxf(highest, at)

	# One clip is one full cycle: two footfalls.
	var cadence: float = 2.0 / clip.length
	var reach: float = highest - lowest
	var ratio: float = RUN_STEP_PER_HEIGHT if running else WALK_STEP_PER_HEIGHT
	var step: float = height * ratio

	print("%-12s cycle %.3f s   cadence %.0f steps/min" % [
		clip_name, clip.length, cadence * 60.0
	])
	print("%-12s foot travel %.3f m   step at this height %.3f m   slide %.0f%%" % [
		"", reach, step, (1.0 - reach / step) * 100.0
	])
	print("%-12s looks right at %.2f m/s\n" % ["", cadence * step])


## Which way the rig faces, read off the feet rather than assumed: a toe reaches
## further forward than its ankle whichever axis forward turns out to be.
func _forward(skeleton: Skeleton3D) -> String:
	var ankle: Vector3 = skeleton.get_bone_global_rest(
		skeleton.find_bone("mixamorig_LeftFoot")
	).origin
	var toe: Vector3 = skeleton.get_bone_global_rest(
		skeleton.find_bone("mixamorig_LeftToe_End")
	).origin
	return "+Z" if toe.z > ankle.z else "-Z"


func _height(node: Node) -> float:
	var tallest: float = 0.0
	for found: Node in _every(node):
		var mesh: MeshInstance3D = found as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			tallest = maxf(tallest, mesh.mesh.get_aabb().size.y)
	return tallest


func _first(node: Node, of_class: String) -> Node:
	if node.get_class() == of_class:
		return node
	for child: Node in node.get_children():
		var deeper: Node = _first(child, of_class)
		if deeper != null:
			return deeper
	return null


func _every(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(_every(child))
	return found
