class_name GrassField
extends RefCounted

## Tells the grass where the walker is.
##
## The shader is a pure function of one point: grass within reach of it leans
## away, and grass anywhere else stands up. **All of the softness is here.** The
## point handed to the shader lags behind the player, so a blade the player has
## just left is still inside the reach of a centre that has not caught up — and
## it rises over the fraction of a second the centre takes to arrive rather than
## snapping upright the instant a foot leaves it.
##
## That is a lag, not a memory. Nothing records where anybody has been, so there
## is no trail behind the player and none is claimed.
##
## It finds its materials once, from the map's own tile library: a `GridMap`
## draws every cell of an item with that item's material, so one material covers
## every patch of grass on a map and there is nothing to do per cell.

const POSITION: String = "walker_position"
const STRENGTH: String = "walker_strength"

## How fast the centre catches up, per second.
##
## Read as: after one second it has closed all but `e^-6` of the gap, so about a
## quarter of a second to arrive. Slower and the grass opens behind the player;
## faster and there is no recovery to see.
const FOLLOW_PER_SECOND: float = 6.0

## How close is close enough to stop moving. Below this the centre is parked
## rather than crawling, which keeps a still player from writing a uniform every
## frame forever.
const ARRIVED: float = 0.001

var _materials: Array[ShaderMaterial] = []
var _centre: Vector3 = Vector3.ZERO
var _strength: float = 1.0


## Collects the grass materials a map draws with. Safe to call again — a warp
## changes the map, and the materials with it.
func of_map(map: VltWorldMap) -> void:
	_materials = []
	if map == null:
		return

	for layer: GridMap in [map.terrain, map.blocking, map.decor]:
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


## Moves the centre towards where the player is drawn, and tells the grass.
##
## The smoothing is `1 - e^(-rate * delta)` rather than a fixed fraction per
## frame. A fixed fraction makes the grass recover faster on a fast machine,
## which is the sort of difference nobody attributes to the frame rate.
func follow(where: Vector3, delta: float) -> void:
	if not where.is_finite() or delta < 0.0:
		return

	if _centre.distance_to(where) <= ARRIVED:
		_centre = where
	else:
		_centre = _centre.lerp(where, 1.0 - exp(-FOLLOW_PER_SECOND * delta))

	_push()


## Puts the walker somewhere at once, with no lag. What a warp and a defeat need:
## letting the centre travel would draw a parting sweeping across the map.
func place(where: Vector3) -> void:
	if not where.is_finite():
		return
	_centre = where
	_push()


## Fades the effect out without moving the centre somewhere untrue. A battle
## hides the world; grass bent around a player who is not there is worse than
## grass that stands up.
func set_strength(strength: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)
	_push()


## Where the grass currently thinks the walker is.
func centre() -> Vector3:
	return _centre


func material_count() -> int:
	return _materials.size()


func _push() -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(POSITION, _centre)
		material.set_shader_parameter(STRENGTH, _strength)
