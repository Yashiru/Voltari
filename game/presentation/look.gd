@tool
class_name Look
extends RefCounted

## The look's vocabulary, and how it is put onto a scene.
##
## The look is one file (`comic_look.gdshaderinc`) but it reaches the screen
## through five shaders and four kinds of node, and until now there was no way to
## change it that did not mean editing a file and rebuilding a library. This is
## the missing half: given any node, hand back every material under it that
## carries the look, so a value can be pushed onto all of them at once.
##
## It is deliberately **not** a new owner of those materials. Nothing here runs
## every frame and nothing holds state — it is a search and a push, called when a
## human changes their mind. The tile library still writes the look into the
## `MeshLibrary` at build time; this pushes over the top afterwards, which is why
## a style can be switched without rebuilding anything.
##
## Used from three places that must not disagree: the editor's look control, the
## world when it loads, and the creature runtime.

## A uniform no other shader in this project declares. A material is wearing the
## look if its shader has this.
##
## Checked by name rather than by comparing shader paths, because five shaders
## include the look and the list would have to be kept in step with them by hand.
##
## **It has to be a name nothing else uses, and most are not.** `terminator` was
## the first choice and it is wrong: two of the looks declared one of their own, so
## both were being counted as wearing the shared look and handed values meant for
## it. `cast_screen` is only ever declared by the shared look, and it says the right
## thing: this is a surface that knows what to do with a thrown shadow.
const MARK: String = "cast_screen"

## Where the chosen look is recorded, and what it falls back to.
##
## The same file `CreatureView` reads, which is the whole point: the editor
## control used to write to a different path in the placeholder quarantine, so
## switching a look changed a file nothing read and appeared to do nothing at all.
const STORE: String = "res://game/presentation/creature/style.txt"

## The placeholder quarantine's own copy of the store.
##
## The quarantined creature runtime reads from beside itself, so a look recorded
## only in the tracked file would leave the placeholders wearing the previous one
## — which is the split this whole control existed to end. Written when the folder
## is there and ignored when it is not, because a fresh checkout has no `_shared/`.
const QUARANTINE: String = "res://game/assets/placeholders/_shared/style.txt"


## What the look never owns: this surface's own description.
##
## Everything here says something about *this mesh* — its colour, its extent, which
## atlas cell its face is on, what element the creature is — and a look has no
## business overwriting any of it. `wear` leaves them exactly as it found them.
##
## The complement of `CONTROLS`, and a test asserts that the two together are
## exactly the uniforms the shared look declares. That is what stops either list
## going stale: a uniform added to the include has to be classified as one or the
## other, and forgetting fails the suite rather than silently escaping the reset.
const SURFACE: PackedStringArray = [
	"albedo", "albedo_tex", "uv_offset", "face_flat", "accent",
	"shape_centre", "shape_round", "model_base", "model_height",
	"shading_ramp", "look_mode",
]

## Every value a look owns, once each, in the order the pipeline reads them.
##
## **This is the vocabulary**, and writing it down in one place is most of decision
## 0069. There used to be six vocabularies: a shared one plus `toon_*`, `bd_*`,
## `vinyl_*`, `ramp_*` and `typelit_*`, which between them asked the same handful
## of questions under nineteen different names — four shadow tints, four wraps,
## three sky gradients, two halftones, two creases, two rims, and a `terminator`
## that meant one thing in one look and something else on a different scale in
## another. There is one name per question now, so this list is short enough to
## read and a control that moves it means the same thing in every look.
##
## Each entry:
##
## - `name` — the uniform, exactly as the shader spells it
## - `group` — the pipeline stage it belongs to, which is how the panel headings
##   and the shader's own `group_uniforms` stay in step
## - `low` / `high` — present when the panel offers a slider for it. Absent means
##   the value is still part of the vocabulary and still reset by `wear`, it just
##   is not one of the dozen-odd numbers anybody actually reaches for
## - `tint` — present on the colours, which get a picker rather than a slider
## - `looks` — present on the four values that are local to one quantiser. Absent
##   means every look reads it, which after the merge is nearly all of them: the
##   honest answer to "why do all the looks offer the same settings" turned out to
##   be to make it true rather than to hide it
const CONTROLS: Array = [
	{"name": "saturation", "group": "paint", "low": 0.5, "high": 2.0},
	{"name": "lift", "group": "paint", "low": 0.0, "high": 0.3},
	{"name": "fill_ceiling", "group": "paint", "low": 0.3, "high": 1.0},
	{"name": "flat_levels", "group": "paint"},
	{"name": "ground_shade", "group": "paint", "low": 0.0, "high": 0.6},

	{"name": "grain_amount", "group": "grain", "low": 0.0, "high": 0.6},
	{"name": "grain_size", "group": "grain"},
	{"name": "grain_steps", "group": "grain"},

	{"name": "contact_shade", "group": "contact", "low": 0.0, "high": 0.8},
	{"name": "contact_reach", "group": "contact"},

	{"name": "shadow_hue", "group": "shadow", "tint": true},
	{"name": "shadow_depth", "group": "shadow", "low": 0.0, "high": 0.9},
	{"name": "shadow_hue_mix", "group": "shadow", "low": 0.0, "high": 1.0},
	{"name": "shadow_saturate", "group": "shadow", "low": 0.0, "high": 1.0},
	{"name": "accent_shadow", "group": "shadow"},
	{"name": "core_extra", "group": "shadow", "low": 0.0, "high": 0.6,
		"looks": ["comic"]},

	{"name": "light_hue", "group": "lit side", "tint": true},
	{"name": "light_hue_mix", "group": "lit side", "low": 0.0, "high": 1.0},

	{"name": "wrap", "group": "lighting", "low": 0.0, "high": 1.0},
	{"name": "terminator", "group": "lighting", "low": 0.0, "high": 1.0},
	{"name": "edge_pixels", "group": "lighting", "low": 0.5, "high": 4.0},
	{"name": "chatter_amount", "group": "lighting", "low": 0.0, "high": 0.15},
	{"name": "chatter_scale", "group": "lighting"},

	{"name": "bands", "group": "quantiser", "low": 1.0, "high": 8.0,
		"looks": ["bands"]},
	{"name": "core_level", "group": "quantiser", "low": 0.0, "high": 1.0,
		"looks": ["comic"]},
	{"name": "ramp_row", "group": "quantiser", "low": 0.0, "high": 1.0,
		"looks": ["ramp"]},

	{"name": "cast_hardness", "group": "cast shadow", "low": 0.0, "high": 1.0},
	{"name": "cast_screen", "group": "cast shadow", "low": 0.0, "high": 1.2},
	{"name": "cast_line", "group": "cast shadow", "low": 0.0, "high": 0.8},
	{"name": "cast_grip", "group": "cast shadow", "low": 0.0, "high": 0.5},

	{"name": "dots_amount", "group": "screen", "low": 0.0, "high": 1.0},
	{"name": "dots_size", "group": "screen", "low": 3.0, "high": 24.0},
	{"name": "dots_angle", "group": "screen"},
	{"name": "dots_max", "group": "screen"},
	{"name": "dots_reach", "group": "screen"},
	{"name": "dots_darken", "group": "screen", "low": 0.0, "high": 1.0},

	{"name": "core_dots_amount", "group": "fine screen", "low": 0.0, "high": 1.0},
	{"name": "core_dots_size", "group": "fine screen"},
	{"name": "core_dots_turn", "group": "fine screen"},
	{"name": "core_dots_max", "group": "fine screen"},
	{"name": "core_dots_reach", "group": "fine screen"},
	{"name": "core_dots_darken", "group": "fine screen"},

	{"name": "ink_colour", "group": "ink", "tint": true},
	{"name": "edge_line", "group": "ink", "low": 0.0, "high": 0.8},
	{"name": "edge_line_width", "group": "ink"},
	{"name": "crease_ink", "group": "ink", "low": 0.0, "high": 1.0},
	{"name": "crease_bias", "group": "ink"},
	{"name": "crease_width", "group": "ink"},

	{"name": "stucco_amount", "group": "roughcast", "low": 0.0, "high": 0.6},
	{"name": "stucco_coarse", "group": "roughcast"},
	{"name": "stucco_fine", "group": "roughcast"},
	{"name": "stucco_fine_share", "group": "roughcast"},
	{"name": "stucco_pits", "group": "roughcast"},
	{"name": "stucco_lit_share", "group": "roughcast"},

	{"name": "spec_strength", "group": "highlight", "low": 0.0, "high": 2.0},
	{"name": "spec_sharpness", "group": "highlight"},
	{"name": "spec_edge", "group": "highlight"},
	{"name": "spec_softness", "group": "highlight"},
	{"name": "spec_adapt", "group": "highlight", "low": 0.0, "high": 1.0},
	{"name": "spec_tint", "group": "highlight"},
	{"name": "spec_fresnel", "group": "highlight"},

	{"name": "rim_strength", "group": "rim", "low": 0.0, "high": 2.0},
	{"name": "rim_width", "group": "rim", "low": 0.0, "high": 1.0},
	{"name": "rim_colour", "group": "rim", "tint": true},
	{"name": "rim_accent", "group": "rim"},
	{"name": "rim_turn", "group": "rim"},

	{"name": "lamp_warmth", "group": "lamp"},
	{"name": "lamp_steps", "group": "lamp"},
]


## Every name in `CONTROLS`, built once. What `wear` resets.
static var _vocabulary: PackedStringArray = PackedStringArray()


static func vocabulary() -> PackedStringArray:
	if _vocabulary.is_empty():
		for entry: Dictionary in CONTROLS:
			@warning_ignore("return_value_discarded")
			_vocabulary.append(str(entry["name"]))
	return _vocabulary


## The controls one quantiser actually reads, in declaration order.
##
## An entry with no `looks` is read by all five, which after the merge is all but
## four of them. The panel calls this so that it never offers a slider the chosen
## look will ignore — which is what it did for thirteen of its eighteen sliders on
## five looks out of six.
static func controls_for(quantiser: String) -> Array:
	var offered: Array = []
	for entry: Dictionary in CONTROLS:
		if _reads(entry, quantiser):
			offered.append(entry)
	return offered


static func _reads(entry: Dictionary, quantiser: String) -> bool:
	if not entry.has("looks"):
		return true
	@warning_ignore("unsafe_cast")
	var only: Array = entry["looks"] as Array
	return only.has(quantiser)


## The slider range of a control, or a zero-width one when it has no slider.
static func control_range(entry: Dictionary) -> Vector2:
	if not entry.has("low"):
		return Vector2.ZERO
	@warning_ignore("unsafe_cast")
	var low: float = entry["low"] as float
	@warning_ignore("unsafe_cast")
	var high: float = entry["high"] as float
	return Vector2(low, high)


## Every material under `root` that wears the printed look, each once.
##
## Materials are shared resources — ninety-two library items point at a handful of
## them — so the same one turns up many times and setting it twice is wasted work.
static func worn_under(root: Node) -> Array[ShaderMaterial]:
	var found: Array[ShaderMaterial] = []
	var seen: Dictionary[int, bool] = {}
	_gather(root, found, seen)
	return found


## Push one value onto everything under `root`. The live end of a slider.
static func tune(root: Node, name: String, value: Variant) -> int:
	var worn: Array[ShaderMaterial] = worn_under(root)
	for material: ShaderMaterial in worn:
		material.set_shader_parameter(name, value)
	return worn.size()


## Dress everything under `root` in a named look.
##
## Returns how many materials were touched, so a caller can say what happened
## rather than claiming success — zero is the interesting answer, and it means the
## scene builds its world at run time and has nothing to dress yet.
##
## **The whole vocabulary is put back to the shader's defaults first.** Without
## that, a look inherits every value the previous one happened to set and did not:
## `comic-sunday` puts the saturation at 1.55, and switching from it to a look
## whose preset says nothing about saturation used to leave it there. Do that two
## or three times and the world is over-saturated again with nothing in any file
## saying so — which is exactly how it was reported.
##
## Nothing in `SURFACE` is touched: a look does not get to decide what colour a
## crate is or how tall it is.
static func wear(root: Node, style: String) -> int:
	var mode: int = CreatureView.mode_of(style)
	var values: Dictionary[String, Variant] = CreatureView.preset_values(style)
	# The `ramp` quantiser reads its whole light response off a strip, and the
	# creature runtime was the only thing binding one. Without it the sampler falls
	# back to white and the look comes out with no shading at all — which reads as
	# broken rather than as a look.
	var strip: Texture2D = _ramp()
	var worn: Array[ShaderMaterial] = worn_under(root)
	var names: PackedStringArray = vocabulary()
	for material: ShaderMaterial in worn:
		# Null is how a `ShaderMaterial` is told to use the shader's own default
		# rather than a value of its own.
		for name: String in names:
			material.set_shader_parameter(name, null)
		material.set_shader_parameter("look_mode", mode)
		if strip != null:
			material.set_shader_parameter("shading_ramp", strip)
		for name: String in values:
			material.set_shader_parameter(name, values[name])
	return worn.size()


## The shading strip, loaded once. Absent from a checkout without it, in which
## case the `ramp` look shades flat and says nothing — the same fallback the
## creature runtime has always had.
static var _strip: Texture2D = null
static var _looked_for_strip: bool = false


static func _ramp() -> Texture2D:
	if not _looked_for_strip:
		_looked_for_strip = true
		var path: String = CreatureView.SHARED + CreatureView.RAMP_FILE
		if ResourceLoader.exists(path):
			_strip = ResourceLoader.load(path, "Texture2D") as Texture2D
	return _strip


## What a value actually is on the surfaces under `root`, rather than what a file
## says it ought to be.
##
## A control that starts its sliders from a preset is lying whenever the preset is
## silent — and a preset is silent about most of the vocabulary. The answer wanted
## is the one the shader will use, which is the material's own value when it has
## one and the shader's declared default when it does not.
##
## `NAN` when nothing under `root` wears the look, which a caller must handle: a
## slider cannot be placed against an answer that does not exist.
static func reading(root: Node, name: String) -> float:
	var held: Variant = held_value(root, name)
	if typeof(held) == TYPE_FLOAT:
		@warning_ignore("unsafe_cast")
		return held as float
	if typeof(held) == TYPE_INT:
		@warning_ignore("unsafe_cast")
		return float(held as int)
	return NAN


## The same answer, whatever its type — the colours need it too.
static func held_value(root: Node, name: String) -> Variant:
	var worn: Array[ShaderMaterial] = worn_under(root)
	if worn.is_empty():
		return null
	var material: ShaderMaterial = worn[0]
	var held: Variant = material.get_shader_parameter(name)
	if held != null:
		return held
	# Unset on the material, so the shader's own default is what will be used.
	# There is no way to read one off a `Shader`; the server holds them.
	return RenderingServer.shader_get_parameter_default(material.shader.get_rid(), name)


## What the surfaces under `root` are set to, spelled the way a preset spells it:
## every look value that differs from the shader's own default, and nothing else.
##
## **That is a complete preset, not a partial one.** `wear` puts the whole
## vocabulary back to the defaults before applying one, so a value left out here is
## the default rather than whatever the previous look left behind — which means
## naming only the differences says exactly as much as naming all sixty-eight, and
## produces a file somebody can read.
static func settings_under(root: Node) -> Dictionary[String, Variant]:
	var settings: Dictionary[String, Variant] = {}
	var worn: Array[ShaderMaterial] = worn_under(root)
	if worn.is_empty():
		return settings
	var material: ShaderMaterial = worn[0]
	for name: String in vocabulary():
		var held: Variant = material.get_shader_parameter(name)
		if held == null:
			continue
		var fallback: Variant = RenderingServer.shader_get_parameter_default(
			material.shader.get_rid(), name
		)
		if not _same(held, fallback):
			settings[name] = held
	return settings


## Whether two shader values are the same number or the same colour.
##
## `==` on a float that has been through a slider and back is never true, so a
## comparison by identity would call every value different and write a preset of
## sixty-eight lines every time.
static func _same(left: Variant, right: Variant) -> bool:
	if typeof(left) != typeof(right):
		return false
	if typeof(left) == TYPE_COLOR:
		@warning_ignore("unsafe_cast")
		return (left as Color).is_equal_approx(right as Color)
	if typeof(left) == TYPE_FLOAT or typeof(left) == TYPE_INT:
		@warning_ignore("unsafe_cast")
		return is_equal_approx(float(left as float), float(right as float))
	return left == right


## The look the game is wearing.
static func chosen() -> String:
	return CreatureView.roster_style()


## Records a look as the one the game wears. The editor control's only write.
static func choose(style: String) -> Error:
	var wrote: Error = _record(STORE, style)
	if wrote != OK:
		return wrote
	if DirAccess.dir_exists_absolute(QUARANTINE.get_base_dir()):
		return _record(QUARANTINE, style)
	return OK


static func _record(path: String, style: String) -> Error:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(style)
	file.close()
	return OK


## Whether a shader carries the look. Answered from the uniform list, and cached:
## a scene has thousands of materials and a handful of shaders between them.
static var _wearing: Dictionary[int, bool] = {}


static func _carries_look(shader: Shader) -> bool:
	var key: int = shader.get_instance_id()
	if _wearing.has(key):
		return _wearing[key]
	var carries: bool = false
	for entry: Dictionary in shader.get_shader_uniform_list(true):
		if str(entry["name"]) == MARK:
			carries = true
			break
	_wearing[key] = carries
	return carries


static func _keep(material: Material, into: Array[ShaderMaterial], seen: Dictionary[int, bool]) -> void:
	var dressed: ShaderMaterial = material as ShaderMaterial
	if dressed == null or dressed.shader == null:
		return
	if seen.has(dressed.get_instance_id()):
		return
	if not _carries_look(dressed.shader):
		return
	seen[dressed.get_instance_id()] = true
	into.append(dressed)


static func _keep_mesh(mesh: Mesh, into: Array[ShaderMaterial], seen: Dictionary[int, bool]) -> void:
	if mesh == null:
		return
	for surface: int in range(mesh.get_surface_count()):
		_keep(mesh.surface_get_material(surface), into, seen)


## The four places a material hides, and they are all different.
##
## A mesh instance can carry one override for the whole node and one per surface,
## on top of whatever the mesh resource itself holds. A `GridMap` holds none: its
## materials live inside the `MeshLibrary`, on the meshes, which is why switching
## a look used to mean rebuilding that library. A particle system — the lawn — puts
## its material on the node and its mesh in a draw pass.
static func _gather(node: Node, into: Array[ShaderMaterial], seen: Dictionary[int, bool]) -> void:
	var drawn: GeometryInstance3D = node as GeometryInstance3D
	if drawn != null:
		_keep(drawn.material_override, into, seen)

	var mesh_node: MeshInstance3D = node as MeshInstance3D
	if mesh_node != null:
		for surface: int in range(mesh_node.get_surface_override_material_count()):
			_keep(mesh_node.get_surface_override_material(surface), into, seen)
		_keep_mesh(mesh_node.mesh, into, seen)

	var grid: GridMap = node as GridMap
	if grid != null and grid.mesh_library != null:
		for id: int in grid.mesh_library.get_item_list():
			_keep_mesh(grid.mesh_library.get_item_mesh(id), into, seen)

	var particles: GPUParticles3D = node as GPUParticles3D
	if particles != null:
		_keep_mesh(particles.draw_pass_1, into, seen)
		_keep_mesh(particles.draw_pass_2, into, seen)

	for child: Node in node.get_children():
		_gather(child, into, seen)
