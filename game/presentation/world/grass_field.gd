class_name GrassField
extends RefCounted

## Tells the grass what the walker is doing.
##
## The shader holds no memory at all — it is a function of the moment. Everything
## with a past lives here, and there is more of it than a position:
##
## - **Two centres.** One tight to the player, one trailing. Grass the trailing
##   centre still covers but the leading one has left is grass just stepped off,
##   and the shader uses the gap between them to hold it down and ring it back
##   up. That is a wake without a memory: nothing records where anybody has been.
## - **A heading**, so grass splays along the path rather than opening in a
##   circle. A circle is a force field; a path is somebody walking.
## - **A speed**, so a player who stops stops pushing grass aside and simply
##   stands in it.
##
## Every one of them is smoothed the same way, and none of them by a fixed
## fraction per frame: `1 - e^(-rate * delta)` gives the same motion at thirty
## frames a second and at two hundred and forty, and the alternative is grass
## that recovers faster on a better machine.

const POSITION: String = "walker_position"
const WAKE: String = "walker_wake"
const HEADING: String = "walker_heading"
const SPEED: String = "walker_speed"
const STRENGTH: String = "walker_strength"

## How fast the leading centre catches up, per second. Tight: this one is
## supposed to be under the player's feet.
const FOLLOW_PER_SECOND: float = 14.0

## How fast the trailing centre catches up. The gap between the two is the wake,
## so this number is how long grass stays down behind somebody — about a third of
## a second, which is long enough to read as a footprint and short enough not to
## look like damage.
const WAKE_PER_SECOND: float = 3.2

## How fast the heading and the speed settle. Slower than the centre on purpose:
## a heading that snapped would flick the splay through ninety degrees the frame
## a player turned a corner.
const HEADING_PER_SECOND: float = 8.0
const SPEED_PER_SECOND: float = 6.0

## How fast anybody walks, in metres a second, for the purpose of deciding
## whether they are moving. Not a rule about movement — the world owns that — but
## the scale this converts a velocity into "pushing" on.
const BRISK: float = 3.0

## Close enough to have arrived. Below this a still player stops writing uniforms
## that cannot change anything.
const ARRIVED: float = 0.0005

var _materials: Array[ShaderMaterial] = []
var _centre: Vector3 = Vector3.ZERO
var _wake: Vector3 = Vector3.ZERO
var _heading: Vector3 = Vector3(0.0, 0.0, 1.0)
var _speed: float = 0.0
var _strength: float = 1.0
var _previous: Vector3 = Vector3.ZERO
var _started: bool = false


## Collects the grass materials a map draws with. Safe to call again — a warp
## changes the map, and the materials with it.
func of_map(map: VltWorldMap) -> void:
	if map == null:
		_materials = []
		return
	of_layers([map.terrain, map.blocking, map.decor])


## The same, from any set of layers. The preview harness builds its own grid and
## has no map to hand, and giving it a second way in would give it a second thing
## to be wrong about.
func of_layers(layers: Array[GridMap]) -> void:
	_materials = []
	for layer: GridMap in layers:
		_collect(layer)


## Everything is drawn from a mesh library, and the same library is usually on
## all three layers — so a material found twice is stored once. Without that,
## every uniform would be written three times a frame for no effect.
func _collect(layer: GridMap) -> void:
	if layer == null or layer.mesh_library == null:
		return

	for id: int in layer.mesh_library.get_item_list():
		var mesh: Mesh = layer.mesh_library.get_item_mesh(id)
		if mesh == null:
			continue
		for surface: int in range(mesh.get_surface_count()):
			var material: ShaderMaterial = mesh.surface_get_material(surface) as ShaderMaterial
			if material != null and not _materials.has(material):
				_materials.append(material)


## Moves everything towards what the walker is doing, and tells the grass.
func follow(where: Vector3, delta: float) -> void:
	if not where.is_finite() or delta < 0.0:
		return
	if not _started:
		place(where)
		return

	_track_motion(where, delta)

	_centre = _towards(_centre, where, FOLLOW_PER_SECOND, delta)
	_wake = _towards(_wake, where, WAKE_PER_SECOND, delta)
	# Only when time passed. A frame of no time that moved the mark would erase
	# the travel the next frame is about to measure against it.
	if delta > 0.0:
		_previous = where
	_push()


## Reads the velocity before the centres move, because the centres are what the
## velocity is being measured against.
##
## A player who is barely moving keeps the heading they had. A zero heading is
## not a direction, and handing one to the shader would collapse the splay to
## whatever the arithmetic happened to produce.
func _track_motion(where: Vector3, delta: float) -> void:
	if delta <= 0.0:
		return

	var travelled: Vector3 = where - _previous
	travelled.y = 0.0

	var pace: float = travelled.length() / delta
	_speed = _eased(_speed, clampf(pace / BRISK, 0.0, 1.0), SPEED_PER_SECOND, delta)

	if travelled.length_squared() > 0.0:
		var going: Vector3 = travelled.normalized()
		_heading = _towards(_heading, going, HEADING_PER_SECOND, delta)
		if _heading.length_squared() > 0.0:
			_heading = _heading.normalized()


## Puts the walker somewhere at once, with no lag and no wake.
##
## What a warp and a defeat need: letting the centres travel would draw a parting
## sweeping across the map, and letting the wake lag would leave a trail from
## somewhere the player never was.
func place(where: Vector3) -> void:
	if not where.is_finite():
		return
	_centre = where
	_wake = where
	_previous = where
	_speed = 0.0
	_started = true
	_push()


## Fades the effect out without moving anything somewhere untrue. A battle hides
## the world; grass bent around a player who is not there is worse than grass
## that stands up.
func set_strength(strength: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)
	_push()


func centre() -> Vector3:
	return _centre


func wake() -> Vector3:
	return _wake


func heading() -> Vector3:
	return _heading


func speed() -> float:
	return _speed


func material_count() -> int:
	return _materials.size()


## Sets one shader value on every grass material.
##
## For the preview harness, which exists so that a change can be judged by
## looking rather than by argument — and judging means rendering twice with one
## number different.
func tune(name: String, value: float) -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(name, value)


## Exponential smoothing, frame-rate independent. `rate` is how much of the gap
## is closed per second, read through `1 - e^(-rate * t)`.
static func _towards(from: Vector3, to: Vector3, rate: float, delta: float) -> Vector3:
	if from.distance_to(to) <= ARRIVED:
		return to
	return from.lerp(to, 1.0 - exp(-rate * delta))


static func _eased(from: float, to: float, rate: float, delta: float) -> float:
	return lerpf(from, to, 1.0 - exp(-rate * delta))


func _push() -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(POSITION, _centre)
		material.set_shader_parameter(WAKE, _wake)
		material.set_shader_parameter(HEADING, _heading)
		material.set_shader_parameter(SPEED, _speed)
		material.set_shader_parameter(STRENGTH, _strength)
