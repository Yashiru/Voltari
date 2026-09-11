extends SceneTree

## Headless check of the species eye wiring.
##
## Godot cannot render without a display, so this asserts the three things that
## can be observed without one: the overlay surface is found and rebound to the
## shader, the expression timeline loads, and the state looked up at a given
## moment of a clip is the one the export recorded.
##
##     godot --headless --script game/assets/species/_shared/check_eye_states.gd
##
## The assertions run on the first processed frame, not in _initialize: a node
## added to the tree is not ready until the loop turns over once, and checking
## earlier reads empty state and reports a failure that is not there.

const SCENE: String = "res://game/assets/species/pm0001_00/pm0001_00.tscn"

## The damage clip stays inside the atlas's first column, which is exactly why it
## could not catch the column mapping being wrong. The faint clip reaches state
## 6 — second column, third row — so both axes are now exercised.
const CLIP_A: String = "ba30_damageS01"
const PROBES_A: Array[Vector2] = [
	Vector2(0.00, 3.0),
	Vector2(0.40, 2.0),
	Vector2(0.49, 1.0),
	Vector2(0.55, 0.0),
]

const CLIP_B: String = "ba41_down01"
const PROBES_B: Array[Vector2] = [
	Vector2(0.02, 0.0),
	Vector2(0.50, 6.0),
	Vector2(1.30, 3.0),
]

var _root: Node3D = null
var _done: bool = false


func _initialize() -> void:
	var packed: PackedScene = load(SCENE) as PackedScene
	if packed == null:
		push_error("cannot load " + SCENE)
		quit(1)
		return
	_root = packed.instantiate() as Node3D
	get_root().add_child(_root)


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	quit(_check())
	return true


func _check() -> int:
	var failures: int = 0

	var materials: Array[ShaderMaterial] = _root.get("_eye_materials")
	print("overlay surfaces rebound: ", materials.size())
	if materials.is_empty():
		push_error("no EyeOverlay surface was rebound to the shader")
		return 1

	var clips: Dictionary = _root.get("_eye_clips")
	print("clips carrying expressions: ", clips.size())
	for clip: String in [CLIP_A, CLIP_B]:
		if not clips.has(clip):
			push_error("no timeline for " + clip)
			return 1

	var player: AnimationPlayer = _find_player(_root)
	if player == null:
		push_error("no AnimationPlayer")
		return 1

	failures += _check_parts(player)

	# Playing, then scrubbed while paused. The second case is what the editor's
	# Animation panel does, and it is the one that used to leave the eyes frozen
	# while the body moved.
	for playing: bool in [true, false]:
		var how: String = "playing" if playing else "scrubbed while paused"
		for pair: Array in [[CLIP_A, PROBES_A], [CLIP_B, PROBES_B]]:
			var clip: String = pair[0]
			@warning_ignore("unsafe_call_argument")
			var probes: Array[Vector2] = pair[1]
			print("  %s, %s:" % [clip, how])
			player.play(clip)
			if not playing:
				player.pause()
			for probe: Vector2 in probes:
				player.seek(probe.x, true)
				_root.call("_process", 0.0)
				failures += _assert_state(materials[0], probe)
	return 1 if failures > 0 else 0


## The vines are their own meshes, stowed to a stub outside the physical attack.
## Left permanently visible they hang off the model as stray filaments, so the
## interesting assertion is that they are *hidden* most of the time.
func _check_parts(player: AnimationPlayer) -> int:
	var parts: Array[MeshInstance3D] = _root.get("_stowable")
	print("  stowable parts: ", parts.size())
	if parts.is_empty():
		push_error("no stowable part was found")
		return 1

	# Typed triples rather than a nested Array: Voltari promotes an untyped
	# argument to an error, and a nested Array's elements are Variant.
	var clips: PackedStringArray = ["ba10_waitA01", "ba20_buturi01", "ba20_buturi01"]
	var times: PackedFloat32Array = [0.5, 0.5, 1.6]
	var wants: Array[bool] = [false, true, false]

	var failures: int = 0
	for i: int in range(clips.size()):
		player.play(clips[i])
		player.seek(times[i], true)
		_root.call("_process", 0.0)
		var out: bool = parts[0].visible
		print("    %s at %.2fs  vines out: %s  want %s  %s"
			% [clips[i], times[i], str(out), str(wants[i]),
				"ok" if out == wants[i] else "WRONG"])
		if out != wants[i]:
			failures += 1
	return failures


## The atlas is two columns of four rows, walked a column at a time.
func _assert_state(material: ShaderMaterial, probe: Vector2) -> int:
	var state: int = int(probe.y)
	@warning_ignore("integer_division")
	var want: Vector2 = Vector2(float(state / 4) * 0.5, -float(state % 4) * 0.25)
	var got: Variant = material.get_shader_parameter("uv_offset")
	var ok: bool = false
	if typeof(got) == TYPE_VECTOR2:
		@warning_ignore("unsafe_cast")
		var offset: Vector2 = got as Vector2
		ok = offset.is_equal_approx(want)
	print("    t=%.2fs  state %d  want %s  got %s  %s"
		% [probe.x, state, str(want), str(got), "ok" if ok else "WRONG"])
	return 0 if ok else 1


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null
