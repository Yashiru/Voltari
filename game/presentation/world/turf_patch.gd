@tool
class_name TurfPatch
extends GPUParticles3D

## A patch of short lawn on the ground.
##
## **Turf is not grass**, in this project's vocabulary. The tall tufts are map
## items with their own model and their own shader (`grass_parting.gdshader`).
## This is the few centimetres of lawn on the soil underneath, and the two are
## meant to be seen together: tufts standing in turf.
##
## Drop one on a map, give it a size, and it grows. Nothing is stored and nothing
## is baked — where each blade stands is worked out on the GPU from its own index,
## so moving the patch or changing its density costs a number and no rebuild.
##
## It builds its own blade, its own materials and its own particle count on ready,
## so a scene file holds a position, a size and a density and nothing else. A
## `.tscn` carrying a mesh and two materials would be a copy of this file that
## nobody could fix in one place.

## Where the pieces live. Named rather than preloaded so a missing shader is a
## warning on one patch and not a scene that refuses to open.
const SCATTER_SHADER: String = "res://game/presentation/world/turf_scatter.gdshader"
const BLADE_SHADER: String = "res://game/presentation/world/turf.gdshader"

## The lawn's colour.
##
## Its own, not the ground's underneath. Grass is green whether it comes up
## through soil, sand or stone, and carrying the surface's colour upward would
## give a desert a sand-coloured lawn — a bug that looks like a decision.
const GREEN: Color = Color(0.24, 0.58, 0.20)

## How many blades a square metre carries at each provisional device tier.
##
## A blade is five triangles, and `tools/budget/tiers.json` allows 150,000 for a
## whole frame on the low tier — so a hundred a square metre over a twenty-metre
## view is already 200,000. These are the numbers that make the feature fit, and
## they are guesses at the shape of the problem rather than measurements, for the
## reason that file states: nobody has run this game on a real device yet
## (decision 0048).
const DENSITY: Dictionary[String, float] = {
	"low": 40.0,
	"mid": 110.0,
	"high": 240.0,
}

## The tier assumed when nobody has said. The middle one deliberately: a lawn that
## silently came up at its thinnest would be judged as the look.
const DENSITY_BY_DEFAULT: float = 110.0

## A ceiling on blades in one patch, whatever the density and size ask for.
##
## Not a performance target — it is a guard against a typo. A patch sized in
## hundreds of metres by accident would otherwise ask for tens of millions of
## instances and take the editor down with it.
const MOST_BLADES: int = 200000

## How far above the patch the blades may reach, for the visibility box. Generous:
## a box that is too tight makes the lawn blink out at the edge of the screen,
## which is far worse than a box that is slightly too large.
const HEADROOM: float = 0.5

## How large the patch is, in metres.
@export var patch_size: Vector2 = Vector2(8.0, 8.0):
	set(value):
		patch_size = value
		_rebuild()

## Blades a square metre. The dial this feature scales on.
@export var density: float = DENSITY_BY_DEFAULT:
	set(value):
		density = maxf(value, 0.0)
		_rebuild()

## How tall the tallest blade is, in metres.
@export var blade_height: float = 0.09:
	set(value):
		blade_height = maxf(value, 0.01)
		_rebuild()

## The lawn's colour, exposed so a map can have a drier or greener corner without
## a second shader.
@export var colour: Color = GREEN:
	set(value):
		colour = value
		_rebuild()

var _scatter: ShaderMaterial = null
var _blade: ShaderMaterial = null


func _ready() -> void:
	_rebuild()


## How many blades this patch is actually drawing. For a caller that wants to
## count them against a budget — which is the only reason anyone would ask.
func blades() -> int:
	return amount


func _rebuild() -> void:
	if not is_inside_tree():
		return

	var scatter_shader: Shader = ResourceLoader.load(SCATTER_SHADER, "Shader") as Shader
	var blade_shader: Shader = ResourceLoader.load(BLADE_SHADER, "Shader") as Shader
	if scatter_shader == null or blade_shader == null:
		push_warning("no turf shaders — this patch stays bare")
		return

	if _scatter == null:
		_scatter = ShaderMaterial.new()
	_scatter.shader = scatter_shader
	_scatter.set_shader_parameter("patch_size", patch_size)
	_scatter.set_shader_parameter("blade_height", blade_height)

	if _blade == null:
		_blade = ShaderMaterial.new()
	_blade.shader = blade_shader
	# The same look everything else in the world wears, from the same file the
	# creatures and the tiles read. A lawn drawn on the shader's bare defaults
	# would be a patch of plain `comic` in a comic-manga world.
	var look: Dictionary[String, Variant] = CreatureView.preset_values(
		CreatureView.roster_style()
	)
	for name: String in look:
		_blade.set_shader_parameter(name, look[name])
	# After the look, because the world is not a subject and a preset says nothing
	# about either — the same two the tile library sets on every world surface.
	_blade.set_shader_parameter("key_follows_camera", 0.0)
	_blade.set_shader_parameter("shape_round", 0.0)
	_blade.set_shader_parameter("albedo", colour)

	var wanted: int = _wanted_blades()
	_scatter.set_shader_parameter("blade_count", float(wanted))

	amount = wanted
	process_material = _scatter
	draw_pass_1 = _blade_mesh()
	material_override = _blade

	# A blade is placed by its index, not carried by a lifetime, so none of the
	# usual particle timing means anything here. What matters is only that every
	# one of them is alive at once.
	lifetime = 1.0
	explosiveness = 1.0
	fixed_fps = 0
	# World space, not patch space. The wind is a world question — a gust has to
	# cross a patch boundary without restarting — and that is only true if a blade
	# knows where it really stands. See `turf_scatter.gdshader`.
	local_coords = false
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visibility_aabb = AABB(
		Vector3(-patch_size.x * 0.5, 0.0, -patch_size.y * 0.5),
		Vector3(patch_size.x, blade_height + HEADROOM, patch_size.y)
	)
	emitting = true


## Blades wanted for this patch, rounded to the square grid the scatter lays out
## and held under the guard.
func _wanted_blades() -> int:
	var area: float = absf(patch_size.x) * absf(patch_size.y)
	var asked: int = int(area * density)
	return clampi(asked, 1, MOST_BLADES)


## One blade: a tapered strip, three segments and a point.
##
## Built here rather than imported, because it is nine vertices and a file would
## be a thing to keep in step with the shader that reads its `UV.y`.
##
## **Its normals point straight up, not out of its face.** A card shaded by its
## own face normal flips as it turns, and at a hundred blades a square metre that
## reads as flicker. Pointing them up makes a blade shade like the ground it grows
## from, which is what a stylised lawn wants — see `turf.gdshader`.
func _blade_mesh() -> ArrayMesh:
	var points: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var uvs: PackedVector2Array = PackedVector2Array()
	var faces: PackedInt32Array = PackedInt32Array()

	# Four rungs up the blade, narrowing, then a single point at the top. The
	# model is one unit tall and one unit wide: the scatter scales it.
	var rungs: PackedFloat32Array = PackedFloat32Array([0.0, 0.35, 0.7])
	var widths: PackedFloat32Array = PackedFloat32Array([0.5, 0.36, 0.2])

	for rung: int in range(rungs.size()):
		var up: float = rungs[rung]
		var half: float = widths[rung]
		points.append(Vector3(-half, up, 0.0))
		points.append(Vector3(half, up, 0.0))
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(0.0, up))
		uvs.append(Vector2(1.0, up))

	var tip: int = points.size()
	points.append(Vector3(0.0, 1.0, 0.0))
	normals.append(Vector3.UP)
	uvs.append(Vector2(0.5, 1.0))

	for rung: int in range(rungs.size() - 1):
		var low: int = rung * 2
		var high: int = low + 2
		faces.append_array([low, high, low + 1])
		faces.append_array([low + 1, high, high + 1])
	faces.append_array([tip - 2, tip, tip - 1])

	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = faces

	var blade: ArrayMesh = ArrayMesh.new()
	blade.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return blade
