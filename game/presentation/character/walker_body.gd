class_name WalkerBody
extends Node3D

## The character who walks the map.
##
## The creature runtime's opposite number, and deliberately not the same class:
## a creature is seated and faces one way for a whole battle, a character turns
## and its legs have to keep up with the ground. Spec 16 named that difference
## and left characters out; decision 0057 is where they came in.
##
## ## The legs are blended, not switched
##
## Standing, walking and running are one continuous thing and they are played as
## one: a blend along an axis whose unit is **metres a second**, with each clip
## standing at the speed it was authored for. There is no threshold anywhere in
## it, and no speed at which the legs change their mind.
##
## What makes that work rather than merely compile is that the two gaits are held
## **in step**. A walk cycle is 1.03 s and a run cycle is 0.70 s; blended at their
## own rates they drift apart within a second and the mixture reads as a limp.
## Both are driven to turn one cycle in the same time, and that time comes from
## the speed, so whatever mixture is on screen both feet land at the same moment.
## Decision 0075 records what that is worth in centimetres and what was tried
## first.
##
## ## Everything else it does
##
## - **Turns** towards the heading rather than snapping to it. A world that
##   snapped would flick the model through ninety degrees inside one frame, which
##   is the single cheapest thing to get wrong here.
## - **Settles**, rather than cutting to the idle the instant a step ends. Two
##   steps in a row are separated by one frame in which nothing is moving, and
##   without a grace the legs would stutter between them.

## The model, and what to fall back to.
##
## A character that failed to load leaves a capsule rather than nothing: this is
## the player, and a game with no player is not debuggable at all.
const MODEL: String = "res://game/assets/characters/main-char.glb"
const STAND_IN_RADIUS: float = 0.3
const STAND_IN_HEIGHT: float = 1.7

## The surface shader every drawn thing in the game wears.
##
## Named here and again in the tile library, which dresses the map. Two owners
## dress two different things — one writes materials into a `MeshLibrary` at build
## time, one hangs overrides on a node at load time — and neither should have to
## import the other to learn the name of a file. What must not be duplicated is
## the look itself, and that lives once, in `comic_look.gdshaderinc`.
const COMIC_SHADER: String = "res://game/presentation/creature/comic.gdshader"

## The one value the character takes off the shared look.
##
## `shape_round` blends the shading normal towards a sphere's, which rescues a
## creature's soft undulations from a razor terminator. A person is not an ovoid:
## rounding towards one centre bends the arms and legs towards the torso's shading
## and the limbs stop reading as separate from the body.
const CHARACTER_ROUND: float = 0.0

## How long the legs keep going after the ground stops moving.
##
## Chained steps are separated by a single frame at zero speed. Anything shorter
## than one frame's grace makes a held direction flicker between running and
## standing; anything much longer makes a genuine stop look like a skid.
const SETTLE_SECONDS: float = 0.12

## How fast the blend chases the speed, in metres a second per second.
##
## The blend position is not the speed: it is the speed with the corners taken
## off. A stick released goes from full to nothing in one frame, and a body whose
## legs answered that exactly would change gait inside 16 ms — which is a cut
## wearing a blend's clothes. Fast enough that nobody waits for it, slow enough
## that the change of gait is a change of gait.
const BLEND_CHASE: float = 12.0

## What the nodes of the graph are called. Named rather than left to defaults,
## because the name is half of every parameter path and a path built out of
## `Blend2` and `Blend2 2` is a path nobody can read.
const LEGS: String = "legs"
const GAIT: String = "gait"

var _model: Node3D = null
var _player: AnimationPlayer = null
var _tree: AnimationTree = null
var _graph: AnimationNodeBlendTree = null
var _since_moving: float = INF

## The last speed that was really a speed. The grace has to keep playing the gait
## the character *was* using: reading the current speed during it would read the
## zero that started the grace, which is the stutter it exists to prevent.
var _last_speed: float = 0.0

## Where the legs are, which trails where the ground is by `BLEND_CHASE`.
var _shown_speed: float = 0.0
var _height: float = STAND_IN_HEIGHT


func _ready() -> void:
	_build()


## How tall the character is, in metres. What a camera needs to look at a face
## rather than at a pair of feet.
func height() -> float:
	return _height


func has_model() -> bool:
	return _tree != null


## Which slot the legs are mostly playing. The nearest authored gait to the speed
## being shown, or the idle when nothing is.
##
## For a caller that needs to see what the character is doing — which, without a
## display, is only ever a test. A blend has no single clip, so this is the one
## a viewer would name rather than the whole mixture.
func playing() -> String:
	if _tree == null:
		return ""
	var motion: WalkerGait.Motion = WalkerGait.moving_at(_shown_speed)
	return motion.clip if motion.is_moving() else HumanoidClips.IDLE


## How fast the legs are being driven, in metres a second. What `playing()` is
## derived from, for a test that wants the number rather than the name.
func shown_speed() -> float:
	return _shown_speed


## One frame of being a character: turned, walking or standing, at the right rate.
##
## `speed` is the ground speed in metres a second, zero when still. `heading` is
## the way the walker is pointed, as a vector — **not one of four**: movement is
## omnidirectional and the body follows it exactly, because quantising here would
## put the character's shoulders on a grid its feet had already left.
func advance(delta: float, speed: float, heading: Vector2) -> void:
	rotation.y = WalkerGait.turned(rotation.y, WalkerGait.yaw_towards(heading), delta)

	if speed > WalkerGait.STILL:
		_since_moving = 0.0
		_last_speed = speed
	elif _since_moving < INF:
		_since_moving += maxf(delta, 0.0)

	# The grace: a step that has just ended is still a step until the next frame
	# has had its chance to start another.
	var wanted: float = _last_speed if _since_moving <= SETTLE_SECONDS else 0.0
	_shown_speed = move_toward(_shown_speed, wanted, BLEND_CHASE * maxf(delta, 0.0))
	_drive()
	if _tree != null:
		_tree.advance(maxf(delta, 0.0))


## Puts the character on a direction at once, without turning to it. What
## arriving somewhere needs: a warp, a load, a defeat.
func face_at_once(heading: Vector2) -> void:
	rotation.y = WalkerGait.yaw_towards(heading)
	_since_moving = INF
	_last_speed = 0.0
	_shown_speed = 0.0
	_drive()


## One frame of the legs: how much of each, and how fast the cycle turns.
##
## Two mixes and two rates, and every one of the four is a function of the speed
## alone. Nothing here remembers anything, which is what makes a character that
## was teleported mid-stride indistinguishable from one that walked there.
func _drive() -> void:
	if _tree == null:
		return

	var walking: float = WalkerGait.LOOKS_RIGHT_AT[HumanoidClips.WALK]
	var running: float = WalkerGait.LOOKS_RIGHT_AT[HumanoidClips.RUN]

	# Standing to walking, then walking to running. Two mixes rather than one
	# axis, so the idle is never asked to be a fraction of a run.
	_tree.set(
		"parameters/%s/blend_amount" % LEGS, clampf(_shown_speed / maxf(walking, 0.001), 0.0, 1.0)
	)
	_tree.set(
		"parameters/%s/blend_amount" % GAIT,
		clampf((_shown_speed - walking) / maxf(running - walking, 0.001), 0.0, 1.0)
	)

	# In step. Both gaits are driven to turn one cycle in the same time, so
	# whatever mixture is on screen puts both feet down together. A rate is one
	# when the gait is at the speed it was authored for.
	var cycle: float = 1.0 / maxf(_cadence(), 0.001)
	for slot: String in HumanoidClips.GAITS:
		var clip: Animation = _player.get_animation("clips/%s" % slot)
		if clip == null:
			continue
		# Kept inside the band where a cadence still reads as human. Below a walk
		# the arithmetic would slow the legs to a crawl and the body would still be
		# moving; the band is where that error is allowed to be a sliding foot
		# rather than an impossible one.
		_tree.set(
			"parameters/%s/scale" % _rate_of(slot),
			clampf(clip.length / cycle, WalkerGait.SLOWEST_RATE, WalkerGait.FASTEST_RATE)
		)


func _cadence() -> float:
	var walking: Animation = _player.get_animation("clips/%s" % HumanoidClips.WALK)
	var running: Animation = _player.get_animation("clips/%s" % HumanoidClips.RUN)
	if walking == null or running == null:
		return 1.0
	return WalkerGait.cadence_for(_shown_speed, walking.length, running.length)


func _build() -> void:
	if ResourceLoader.exists(MODEL):
		var packed: PackedScene = load(MODEL) as PackedScene
		if packed != null:
			_model = packed.instantiate() as Node3D

	if _model == null:
		_model = _stand_in()
		add_child(_model)
		return

	add_child(_model)
	# Not scaled. The model is 1.7 m with its feet at the origin, which is a
	# person on a two-metre grid — resizing it would be inventing a scale the
	# artist already chose.
	_height = maxf(_measured_height(_model), 0.0)
	_dress()
	_animate()
	_drive()


## Gives the model its clips and the graph that blends them.
##
## Built here rather than authored as a resource: every number in it is measured
## and lives in `WalkerGait`, and a `.tres` holding the same numbers again would
## be a second place for them to be wrong. What the graph *is* — an axis in metres
## a second with a clip at each authored speed — is three lines, and reads better
## as three lines than as a file nobody opens.
func _animate() -> void:
	var clips: AnimationLibrary = HumanoidClips.library()
	if clips.get_animation_list().is_empty():
		push_warning("no character clips were found — the model will stand still")
		return

	_player = AnimationPlayer.new()
	_model.add_child(_player)
	# The clips address `%GeneralSkeleton`, and a unique name resolves from the
	# root of the scene it was instanced from — so the player is rooted at the
	# model rather than at itself.
	_player.root_node = NodePath("..")
	_player.add_animation_library("clips", clips)

	_graph = AnimationNodeBlendTree.new()
	for slot: String in HumanoidClips.GAITS:
		_graph.add_node(slot, _clip(slot))
		var rate: AnimationNodeTimeScale = AnimationNodeTimeScale.new()
		_graph.add_node(_rate_of(slot), rate)
		_graph.connect_node(_rate_of(slot), 0, slot)

	# Walking into running, then standing into whichever of them is on. Both
	# blends are synchronised, so the clip that is being faded out keeps turning
	# rather than freezing part way through a stride and jumping when it comes
	# back.
	_graph.add_node(GAIT, _mixed())
	_graph.connect_node(GAIT, 0, _rate_of(HumanoidClips.WALK))
	_graph.connect_node(GAIT, 1, _rate_of(HumanoidClips.RUN))

	_graph.add_node(HumanoidClips.IDLE, _clip(HumanoidClips.IDLE))
	_graph.add_node(LEGS, _mixed())
	_graph.connect_node(LEGS, 0, HumanoidClips.IDLE)
	_graph.connect_node(LEGS, 1, GAIT)
	_graph.connect_node("output", 0, LEGS)

	_tree = AnimationTree.new()
	_tree.root_node = NodePath("..")
	_model.add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.tree_root = _graph
	# Advanced by hand, from the same `delta` the walker is moved by.
	#
	# The graph is a function of the ground speed, and the ground speed arrives in
	# `advance`. Letting the tree run on its own clock would put the legs one frame
	# behind the body every frame, and would make every test of this class a test
	# of how many frames the harness happened to run. The rest of this repository
	# advances its machines deliberately rather than in the background, and this is
	# the same choice for the same reason.
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_tree.active = true


## One clip, as a node of the graph.
static func _clip(slot: String) -> AnimationNodeAnimation:
	var node: AnimationNodeAnimation = AnimationNodeAnimation.new()
	node.animation = "clips/%s" % slot
	return node


## A two-way mix that keeps both sides turning.
##
## Without `sync` the side being faded out stops where it is, and comes back
## later from a stride nobody was in the middle of.
static func _mixed() -> AnimationNodeBlend2:
	var node: AnimationNodeBlend2 = AnimationNodeBlend2.new()
	node.sync = true
	return node


## What a gait's rate node is called. One rule, so the graph and the parameter
## path cannot drift apart.
static func _rate_of(slot: String) -> String:
	return "%s_rate" % slot


## Puts the printed look on the character.
##
## Override slots rather than materials written into the mesh: the mesh is an
## imported resource, and the tile library's reason for writing into one — a
## `GridMap` cell has nowhere else to put a material — does not apply to a node
## that has slots of its own. This way re-exporting the model needs nothing.
##
## Read from the same style file the creatures and the map read, so the three
## cannot disagree. Unlike the map, which bakes the look into its library, this
## happens every load — so a style switched in the editor shows on the character
## immediately and on the ground after a rebuild.
func _dress() -> void:
	var shader: Shader = ResourceLoader.load(COMIC_SHADER, "Shader") as Shader
	if shader == null:
		push_warning("no shader at %s — the character stays as imported" % COMIC_SHADER)
		return

	var look: Dictionary[String, Variant] = CreatureView.preset_values(
		CreatureView.roster_style()
	)
	for mesh: MeshInstance3D in _meshes_under(_model):
		for surface: int in range(mesh.mesh.get_surface_count()):
			mesh.set_surface_override_material(
				surface, _printed(mesh.mesh.surface_get_material(surface), shader, look)
			)


## One surface's material, carrying its imported colour and texture across.
##
## Anything richer than a colour and a texture is not carried, which is the same
## bargain the map strikes: these are flat-shaded models and there is nothing else
## on them to lose.
static func _printed(
	existing: Material, shader: Shader, look: Dictionary[String, Variant]
) -> ShaderMaterial:
	var printed: ShaderMaterial = ShaderMaterial.new()
	printed.shader = shader

	var standard: StandardMaterial3D = existing as StandardMaterial3D
	if standard != null:
		printed.set_shader_parameter("albedo", standard.albedo_color)
		if standard.albedo_texture != null:
			printed.set_shader_parameter("albedo_tex", standard.albedo_texture)

	for name: String in look:
		printed.set_shader_parameter(name, look[name])
	# After the look: no preset names it, so nothing is taken back.
	printed.set_shader_parameter("shape_round", CHARACTER_ROUND)
	return printed


func _measured_height(node: Node) -> float:
	var tallest: float = 0.0
	for mesh: MeshInstance3D in _meshes_under(node):
		tallest = maxf(tallest, mesh.mesh.get_aabb().size.y)
	return tallest if tallest > 0.0 else STAND_IN_HEIGHT


static func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.mesh != null:
		found.append(mesh)
	for child: Node in node.get_children():
		found.append_array(_meshes_under(child))
	return found


## Feet at the origin, like the model, so nothing downstream has to know which
## one it is looking at.
static func _stand_in() -> Node3D:
	var mesh: MeshInstance3D = MeshInstance3D.new()
	var shape: CapsuleMesh = CapsuleMesh.new()
	shape.radius = STAND_IN_RADIUS
	shape.height = STAND_IN_HEIGHT
	mesh.mesh = shape
	mesh.position = Vector3(0, STAND_IN_HEIGHT * 0.5, 0)
	return mesh
