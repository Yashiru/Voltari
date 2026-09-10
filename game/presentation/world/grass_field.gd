class_name GrassField
extends RefCounted

## Tells the grass which cell was just stepped into.
##
## The shader holds no state: it is handed two cells and how long ago each was
## entered, and it swings whichever of them is still ringing. Everything with a
## past is here, and there is very little of it — **a jostle is one shot**. A cell
## is either ringing or it is not, nothing accumulates, and nothing is recorded
## about where anybody has been.
##
## Two slots because a cell is crossed in about half a second and a swing lasts
## about as long: with one, leaving a cell would cut its swing off mid-air.
##
## It knows nothing about the grid. The world hands over a point — the middle of
## the cell it just moved onto — and the shader compares that against each cell's
## own origin. Nothing here has to agree with anybody about how wide a cell is.

const JOSTLE_A: String = "jostle_a"
const JOSTLE_A_AGE: String = "jostle_a_age"
const JOSTLE_B: String = "jostle_b"
const JOSTLE_B_AGE: String = "jostle_b_age"
const STRENGTH: String = "walker_strength"
const REACH: String = "jostle_reach"
const SECONDS: String = "jostle_seconds"

## How long one swing lasts. **Held here rather than only in the shader**, because
## this is what has to know when a cell has stopped ringing — and two places that
## both know it are two places that disagree the first time one is tuned.
const SWING_SECONDS: float = 0.7

## How much of a cell counts as being in it. A little over half, so the cell
## stepped onto rings and the four beside it do not.
const REACH_OF_A_CELL: float = 0.62

## An age far past the end of any swing. Handed over rather than a flag, so the
## shader has one thing to check instead of two.
const OVER: float = 999.0

var _materials: Array[ShaderMaterial] = []
var _newest: Vector3 = Vector3.ZERO
var _newest_age: float = OVER
var _older: Vector3 = Vector3.ZERO
var _older_age: float = OVER
var _strength: float = 1.0


## Collects the grass materials a map draws with. Safe to call again — a warp
## changes the map, and the materials with it.
func of_map(map: VltWorldMap) -> void:
	if map == null:
		_materials = []
		return
	of_layers([map.terrain, map.blocking, map.decor])

	# How far a jostle reaches comes from the grid the map is painted on, not
	# from a number in a shader. A map on a finer grid rings one of its own cells
	# rather than a metre's worth of somebody else's.
	set_cell_size(map.cell_width())


## The same, from any set of layers. The preview harness builds its own grid and
## has no map to hand, and giving it a second way in would give it a second thing
## to be wrong about.
func of_layers(layers: Array[GridMap]) -> void:
	_materials = []
	for layer: GridMap in layers:
		_collect(layer)


func _collect(layer: GridMap) -> void:
	if layer == null or layer.mesh_library == null:
		return

	# The same library usually sits on all three layers, so a material found
	# twice is stored once. Without that every uniform would be written three
	# times a frame for no effect.
	for id: int in layer.mesh_library.get_item_list():
		var mesh: Mesh = layer.mesh_library.get_item_mesh(id)
		if mesh == null:
			continue
		for surface: int in range(mesh.get_surface_count()):
			var material: ShaderMaterial = mesh.surface_get_material(surface) as ShaderMaterial
			if material != null and not _materials.has(material):
				_materials.append(material)


## Somebody stepped onto a cell. Sets it ringing.
##
## The cell already ringing moves to the second slot rather than being dropped:
## walking is a run of cells and each should finish its swing behind you.
func enter_cell(centre: Vector3) -> void:
	if not centre.is_finite():
		return

	_older = _newest
	_older_age = _newest_age
	_newest = centre
	_newest_age = 0.0
	_push()


## Ages both swings by a frame.
##
## Cheap, and it stops writing once both are over — a still player standing in
## grass costs two comparisons a frame and no uniform writes at all.
func advance(delta: float) -> void:
	if delta <= 0.0 or not settling():
		return

	_newest_age = _aged(_newest_age, delta)
	_older_age = _aged(_older_age, delta)
	_push()


## Ages one swing, and parks it once it is over. Parked rather than left to climb
## so that a session running for an hour hands the shader a number it can still
## compare.
static func _aged(age: float, delta: float) -> float:
	var older: float = age + delta
	return OVER if older >= SWING_SECONDS else older


## Whether anything is still moving because of somebody. Public because "is it
## quiet" is the only question a caller can usefully ask.
func settling() -> bool:
	return _newest_age < SWING_SECONDS or _older_age < SWING_SECONDS


## Nothing is ringing, and nothing was.
##
## What a warp and a defeat need: a swing left over from the map you came from
## would ring a cell on this one that nobody has stepped on.
func quiet() -> void:
	_newest_age = OVER
	_older_age = OVER
	_push()


## Fades the jostle out without pretending nobody is there. A battle hides the
## world, and grass swinging around somebody off screen is worse than grass
## standing still.
func set_strength(strength: float) -> void:
	_strength = clampf(strength, 0.0, 1.0)
	_push()


## Tells the grass how wide a cell is. Called by whoever knows — a map, or a
## harness that built its own grid.
func set_cell_size(metres: float) -> void:
	if metres <= 0.0:
		return
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(REACH, metres * REACH_OF_A_CELL)


func material_count() -> int:
	return _materials.size()


## What the shader is being told, for a test and for the preview harness.
func newest_cell() -> Vector3:
	return _newest


func newest_age() -> float:
	return _newest_age


func older_age() -> float:
	return _older_age


## Sets one shader value on every grass material.
##
## For the preview harness, which exists so that a change can be judged by
## looking rather than by argument — and judging means rendering twice with one
## number different.
func tune(name: String, value: float) -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(name, value)


func _push() -> void:
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(JOSTLE_A, _newest)
		material.set_shader_parameter(JOSTLE_A_AGE, _newest_age)
		material.set_shader_parameter(JOSTLE_B, _older)
		material.set_shader_parameter(JOSTLE_B_AGE, _older_age)
		material.set_shader_parameter(SECONDS, SWING_SECONDS)
		material.set_shader_parameter(STRENGTH, _strength)
