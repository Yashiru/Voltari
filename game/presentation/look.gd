@tool
class_name Look
extends RefCounted

## Finding everything that wears the printed look, and changing it.
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
## Used from two places that must not disagree: the editor's look control, and the
## world when it loads.

## A uniform no other shader in this project declares. A material is wearing the
## look if its shader has this.
##
## Checked by name rather than by comparing shader paths, because five shaders
## include the look and the list would have to be kept in step with them by hand.
##
## **It has to be a name nothing else uses, and most are not.** `terminator` was
## the first choice and it is wrong: `bd` and `typelit` declare one too, so both
## were being counted as wearing the shared look and handed values meant for it.
## `ink` is no better — `bd` has that as well. `cast_screen` is only ever declared
## by the shared look, and it says the right thing: this is a surface that knows
## what to do with a thrown shadow.
const MARK: String = "cast_screen"

## Where the chosen look is recorded, and what it falls back to.
##
## The same file `CreatureView` reads, which is the whole point: the editor
## control used to write to a different path in the placeholder quarantine, so
## switching a look changed a file nothing read and appeared to do nothing at all.
const STORE: String = "res://game/presentation/creature/style.txt"


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
static func wear(root: Node, style: String) -> int:
	# The mode first, and unconditionally. A style that names a look rather than a
	# preset — `toon`, `bd` — carries no values at all, and returning early on that
	# is exactly what used to make picking one of them do nothing at all.
	var mode: int = CreatureView.mode_of(style)
	var values: Dictionary[String, Variant] = CreatureView.preset_values(style)
	# The `ramp` look reads its whole light response off a strip, and the creature
	# runtime was the only thing binding one. Without it the sampler falls back to
	# white and the look comes out with no shading at all — which reads as broken
	# rather than as a look.
	var strip: Texture2D = _ramp()
	var worn: Array[ShaderMaterial] = worn_under(root)
	for material: ShaderMaterial in worn:
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


## The look the game is wearing.
static func chosen() -> String:
	return CreatureView.roster_style()


## The placeholder quarantine's own copy of the store.
##
## The quarantined creature runtime reads from beside itself, so a look recorded
## only in the tracked file would leave the placeholders wearing the previous one
## — which is the split this whole control existed to end. Written when the folder
## is there and ignored when it is not, because a fresh checkout has no `_shared/`.
const QUARANTINE: String = "res://game/assets/placeholders/_shared/style.txt"


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
