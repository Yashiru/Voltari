@tool
class_name Daylight
extends Node3D

## The one sun a scene needs, and the paper it is printed on.
##
## The printed look is lit (decision 0064): it reads `ATTENUATION` to know what
## the sun cannot see, and that is where every cast shadow in the game comes from.
## It follows that **a scene with no directional light renders black** — not dim,
## black, because the look writes the whole surface itself and nothing else writes
## anything. This node is how a scene stops being black, and putting it in one
## place is what stops two scenes from disagreeing about what time of day it is.
##
## One node, two children, no configuration required:
##
## - a `DirectionalLight3D`, the key, casting
## - a `WorldEnvironment` holding the paper the page is printed on
##
## **Exactly one directional light.** The look's sun branch writes the surface;
## every other light adds a warm pool over it. Two suns would write the base twice
## and the shadow tone would come out doubled. The shared look says so at the top
## and this node is the reason it can rely on it.
##
## Built in code rather than saved into each scene, for the same reason the style
## is a file and not a property: a look that lives in two `.tscn` files is a look
## that drifts the first time one of them is opened and saved.

## Where the sun stands, as the direction its light travels.
##
## Down and across rather than overhead: a key at noon flattens everything it
## touches, because the terminator lands where nobody is looking. This is the
## afternoon, which is the hour a cosy scene is nearly always drawn at.
@export var travelling: Vector3 = Vector3(-0.48, -0.66, 0.58):
	set(value):
		travelling = value
		_aim()

## The sun's own colour. Warm, and only just — the shadow is already pushed cool
## and saturated by the look, so the key has to do very little to make the pair
## read as sunlight. Pushed further it stops being a printed page and starts being
## a sunset filter.
@export var warmth: Color = Color(1.0, 0.965, 0.912):
	set(value):
		warmth = value
		if _sun != null:
			_sun.light_color = value

## How hard the sun is.
##
## Short of 1 on purpose. The look writes the lit tone as the paint at full
## strength, and a page's brightest thing is its paper, not its ink — a fill
## printed at the same value as the paper it sits on is what "over-exposed" means
## here. Swept against 1.0 and 0.80 on a dressed scene; 0.88 is where the greens
## stop being neon and the shadows still carry.
@export var brightness: float = 0.88:
	set(value):
		brightness = value
		if _sun != null:
			_sun.light_energy = value

## The colour behind everything. Paper, not sky: the look is a print, and a print
## has a page.
@export var paper: Color = Color(0.937, 0.914, 0.863):
	set(value):
		paper = value
		if _page != null and _page.environment != null:
			_page.environment.background_color = value

## How far the shadow map reaches, in metres.
##
## One orthogonal cascade rather than several splits. The whole cast shadow is
## snapped to a hard edge by the look, so the resolution a far cascade would buy is
## thrown away — and a single cascade is the cheapest directional shadow there is,
## which matters on the Forward Mobile renderer this project uses.
@export var shadow_reach: float = 48.0:
	set(value):
		shadow_reach = value
		if _sun != null:
			_sun.directional_shadow_max_distance = value

## Sideways skew of the shadow map's depth test, in metres.
##
## Raised well above Godot's default on purpose. These models are flat-shaded and
## the ground is a single plane a hundred tiles wide, which is the exact case that
## produces shadow acne — a surface shadowing itself in stripes. Snapping the
## shadow to a hard edge makes acne worse, not better, because there is no filter
## left to smear it away.
@export var shadow_bias: float = 0.06

var _sun: DirectionalLight3D = null
var _page: WorldEnvironment = null


func _ready() -> void:
	_build()


## The light itself, for a caller that needs to know where the key is — the battle
## camera frames against it, and a test reads it.
func sun() -> DirectionalLight3D:
	return _sun


func _build() -> void:
	_page = WorldEnvironment.new()
	var page: Environment = Environment.new()
	page.background_mode = Environment.BG_COLOR
	page.background_color = paper
	# The look writes the whole surface and declares `ambient_light_disabled`, so
	# nothing here reaches it. Set anyway, so that a material which is *not* ours —
	# an editor gizmo, a debug mesh — is visible rather than black.
	page.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	page.ambient_light_color = paper
	page.ambient_light_energy = 0.35
	_page.environment = page
	add_child(_page)

	_sun = DirectionalLight3D.new()
	_sun.light_color = warmth
	_sun.light_energy = brightness
	_sun.shadow_enabled = true
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = shadow_reach
	_sun.shadow_bias = shadow_bias
	# Normal bias pushes the test along the surface normal, which is what stops a
	# flat-shaded plane striping itself. Cheap here because the edge is snapped
	# afterwards, so the peter-panning it causes never shows.
	_sun.shadow_normal_bias = 0.3
	# The look snaps the edge itself. Blur beyond this only costs samples.
	_sun.shadow_blur = 0.5
	add_child(_sun)
	_aim()


func _aim() -> void:
	if _sun == null:
		return
	var facing: Vector3 = travelling.normalized()
	if facing.length_squared() < 0.5:
		return
	# A light shines down its own -Z, so aiming it at a point one metre along the
	# travel direction is the same as saying which way the light goes.
	_sun.look_at_from_position(Vector3.ZERO, facing, Vector3.UP)
