class_name WalkerBody
extends Node3D

## The character who walks the map.
##
## The creature runtime's opposite number, and deliberately not the same class:
## a creature is seated and faces one way for a whole battle, a character turns
## and its legs have to keep up with the ground. Spec 16 named that difference
## and left characters out; decision 0057 is where they came in.
##
## Three things it does, and it does them every frame because all three are
## continuous:
##
## - **Turns** towards the grid facing rather than snapping to it. A four-facing
##   world that snapped would flick the model through ninety degrees inside one
##   frame, which is the single cheapest thing to get wrong here.
## - **Chooses a gait** from the ground speed, and plays it at the rate that gait
##   was authored for (`WalkerGait`).
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

## How long one clip takes to give way to the next. Long enough that no
## transition is a cut, short enough that a stop reads as a stop.
const BLEND_SECONDS: float = 0.18

## How long the legs keep going after the ground stops moving.
##
## Chained steps are separated by a single frame at zero speed. Anything shorter
## than one frame's grace makes a held direction flicker between running and
## standing; anything much longer makes a genuine stop look like a skid.
const SETTLE_SECONDS: float = 0.12

var _model: Node3D = null
var _player: AnimationPlayer = null
var _playing: String = ""
var _since_moving: float = INF

## The last speed that was really a speed. The grace has to keep playing the gait
## the character *was* using: reading the current speed during it would read the
## zero that started the grace, which is the stutter it exists to prevent.
var _last_speed: float = 0.0
var _height: float = STAND_IN_HEIGHT


func _ready() -> void:
	_build()


## How tall the character is, in metres. What a camera needs to look at a face
## rather than at a pair of feet.
func height() -> float:
	return _height


func has_model() -> bool:
	return _player != null


## Which clip is running, or empty. For a caller that needs to see what the
## character is doing — which, without a display, is only ever a test.
func playing() -> String:
	return _playing


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
	var effective: float = _last_speed if _since_moving <= SETTLE_SECONDS else 0.0
	_show(WalkerGait.moving_at(effective))


## Puts the character on a direction at once, without turning to it. What
## arriving somewhere needs: a warp, a load, a defeat.
func face_at_once(heading: Vector2) -> void:
	rotation.y = WalkerGait.yaw_towards(heading)
	_since_moving = INF
	_last_speed = 0.0
	_show(WalkerGait.moving_at(0.0))


func _show(motion: WalkerGait.Motion) -> void:
	if _player == null:
		return

	var wanted: String = motion.clip if motion.is_moving() else WalkerGait.IDLE_CLIP
	if not _player.has_animation(wanted):
		return

	if wanted != _playing:
		# Blended rather than cut. Every change of clip here is a change of
		# posture, and a cut between two postures is the thing that reads as a
		# glitch rather than as a decision.
		_player.play(wanted, BLEND_SECONDS)
		_playing = wanted

	# Set every frame rather than on the change: the rate follows the speed, and
	# the speed can move without the clip doing so.
	_player.speed_scale = motion.rate if motion.is_moving() else 1.0


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
	_player = _player_under(_model)
	# Not scaled. The model is 1.7 m with its feet at the origin, which is a
	# person on a two-metre grid — resizing it would be inventing a scale the
	# artist already chose.
	_height = maxf(_measured_height(_model), 0.0)
	_dress()
	_show(WalkerGait.moving_at(0.0))


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


static func _player_under(node: Node) -> AnimationPlayer:
	for child: Node in node.get_children():
		if child is AnimationPlayer:
			return child as AnimationPlayer
		var deeper: AnimationPlayer = _player_under(child)
		if deeper != null:
			return deeper
	return null


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
