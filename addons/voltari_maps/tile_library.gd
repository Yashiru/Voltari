@tool
class_name VltTileLibrary
extends RefCounted

## A folder of models, turned into something you can paint with.
##
## A `GridMap` paints from a `MeshLibrary`, and building one by hand is ninety
## drag-and-drops. This reads a folder and produces the library.
##
## **The one property that matters is that item ids never move.** A `GridMap`
## stores an id per cell, so an id that means "fence" today and "cactus" after a
## rebuild rewrites every painted map, silently and everywhere at once. So:
##
## - An existing library is loaded and added to, never replaced.
## - An item keeps its id for as long as its name is the same.
## - A model removed from the folder keeps its item. Freeing the id would let a
##   later model take it, which is the corruption above with extra steps.
##
## Renaming a model file is therefore a new item, and the old one lingers. That
## is the trade this makes: a stale entry in a palette is a nuisance, and a
## reshuffled id is a day of work.
##
## **No collision shapes.** The overworld has no physics — movement is a cell
## lookup and what stops you is a painted layer (spec 14, sections 1 and 3). A
## shape on a tile would be a second answer to a question already answered, and
## the two would disagree the first time somebody painted only one of them.

## What is read. Everything Godot imports as a scene, plus scenes themselves —
## a model somebody has already adjusted is as good a source as the file it came
## from.
##
## An `Array[String]` rather than a `PackedStringArray`, because the packed form
## is a call and a call is not a constant expression in GDScript.
const SOURCES: Array[String] = [
	".glb", ".gltf", ".fbx", ".obj", ".blend", ".dae", ".tscn", ".scn"
]


## The shader every item wears, and the one the grass wears instead.
##
## Applied here because this is where the meshes are made: the imported material
## has to be *replaced*, not layered over, and doing it anywhere else would mean
## a second pass that undoes itself on the next rebuild.
##
## Two shaders and not one because `render_mode` is per shader: a blade is a card
## and draws from both sides, a crate is a closed mesh and culls. They share the
## look itself through `comic_look.gdshaderinc`, so there is still one terminator
## and one screentone in the project.
const COMIC_SHADER: String = "res://game/presentation/creature/comic.gdshader"
const PARTING_SHADER: String = "res://game/presentation/world/grass_parting.gdshader"

## The only shader values this tool owns. Everything else on a dressed material is
## either art direction, which belongs to the shader's own defaults and to the
## named preset, or something the runtime sets every frame.
##
## An `Array[String]`: the packed form is a call, and a call is not a constant
## expression in GDScript.
const OWNED: Array[String] = ["albedo", "albedo_tex", "blade_base", "blade_height"]

## What the world overrides on the shared look, and why each one.
##
## A preset says nothing about either of these — checked against all five — so
## applying them after it takes nothing back.
##
## `key_follows_camera`: a creature is a subject and gets relit every panel so its
## form always reads. The ground is not a subject. A key that swung with the
## camera would slide the shading across the terrain as the player turned, which
## is the one thing a set must never do.
##
## `shape_round`: rounds the shading normal towards a sphere, which rescues a
## creature's soft undulations from a razor terminator. A wall is genuinely flat,
## and bending its shadow would contradict what the eye can see of its edge.
const WORLD_LOOK: Dictionary[String, float] = {
	"key_follows_camera": 0.0,
	"shape_round": 0.0,
}


## What one run did. Returned rather than printed so a caller can show it, and
## so a test can read it.
class Report:
	extends RefCounted

	## Items created this run, by name.
	var added: PackedStringArray = PackedStringArray()

	## Items that already existed and kept their id.
	var kept: PackedStringArray = PackedStringArray()

	## Files that looked like models and yielded no mesh.
	var skipped: PackedStringArray = PackedStringArray()

	## Items in the library that no file in the folder produces any more. Named
	## rather than deleted.
	var orphaned: PackedStringArray = PackedStringArray()

	## Items whose material was swapped for the parting shader.
	var parting: PackedStringArray = PackedStringArray()

	## Items whose material was swapped for the printed look.
	var printed: PackedStringArray = PackedStringArray()

	## The named look everything was dressed in, for a caller that wants to show
	## which one a library is wearing — it is baked in, so it is worth saying.
	var look: String = ""

	var problems: PackedStringArray = PackedStringArray()
	var output: String = ""

	func total() -> int:
		return added.size() + kept.size()

	func worked() -> bool:
		return problems.is_empty()


## Reads `folder`, writes `output`, and says what it did.
static func build(folder: String, output: String, parting: String = "") -> Report:
	var report: Report = Report.new()
	report.output = output

	var files: PackedStringArray = model_files(folder)
	if files.is_empty():
		report.problems.append("no models found in %s" % folder)
		return report

	var library: MeshLibrary = _existing(output)
	var by_name: Dictionary[String, int] = _index(library)
	var next_id: int = _next_id(library)
	var produced: Dictionary[String, bool] = {}

	for path: String in files:
		var item_name: String = path.get_file().get_basename()
		var mesh: Mesh = mesh_of(path)
		if mesh == null:
			report.skipped.append(path)
			continue

		produced[item_name] = true
		if by_name.has(item_name):
			# The mesh is refreshed and the id is not. Re-exporting a model has
			# to be a safe thing to do, or nobody will fix one.
			library.set_item_mesh(by_name[item_name], mesh)
			report.kept.append(item_name)
			continue

		library.create_item(next_id)
		library.set_item_name(next_id, item_name)
		library.set_item_mesh(next_id, mesh)
		by_name[item_name] = next_id
		report.added.append(item_name)
		next_id += 1

	for item_name: String in by_name:
		if not produced.has(item_name):
			report.orphaned.append(item_name)

	_dress_all(library, by_name, parting, report)

	_bake_previews(library)

	var saved: Error = ResourceSaver.save(library, output)
	if saved != OK:
		report.problems.append("could not write %s (error %d)" % [output, saved])

	return report


## Every file in the folder that Godot could load as a model. Flat, not
## recursive: one folder is one library, which is the rule that makes it obvious
## which palette a model will end up in.
static func model_files(folder: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null:
		return found

	for file: String in directory.get_files():
		# Godot writes an `.import` beside every source it converts. Reading them
		# would double every item and produce a palette of nothing.
		if file.ends_with(".import"):
			continue
		for extension: String in SOURCES:
			if file.to_lower().ends_with(extension):
				found.append("%s/%s" % [folder, file])
				break

	found.sort()
	return found


## The mesh a model file yields, or null.
##
## A model is a scene, and a scene may hold several meshes — a chest and its lid,
## a fence and its post. They are combined into one, because a library item is
## one mesh and dropping all but the first would quietly lose half of what the
## author sees in their own viewer.
static func mesh_of(path: String) -> Mesh:
	var resource: Resource = load(path)

	var direct: Mesh = resource as Mesh
	if direct != null:
		return direct

	var packed: PackedScene = resource as PackedScene
	if packed == null:
		return null

	var root: Node = packed.instantiate()
	var combined: Mesh = _combine(root)
	root.free()
	return combined


# --- reading a scene ---------------------------------------------------------


static func _combine(root: Node) -> Mesh:
	var parts: Array[MeshInstance3D] = []
	_meshes_under(root, parts)
	if parts.is_empty():
		return null

	var first: MeshInstance3D = parts[0]
	if parts.size() == 1 and _relative_to(root, first).is_equal_approx(Transform3D.IDENTITY):
		# The ordinary case, and taking the mesh whole keeps whatever the
		# importer produced — compression, LODs, shadow meshes and all.
		return first.mesh

	var out: ArrayMesh = ArrayMesh.new()
	for part: MeshInstance3D in parts:
		_append(out, part, _relative_to(root, part))

	return out if out.get_surface_count() > 0 else null


static func _meshes_under(node: Node, into: Array[MeshInstance3D]) -> void:
	var instance: MeshInstance3D = node as MeshInstance3D
	if instance != null and instance.mesh != null:
		into.append(instance)
	for child: Node in node.get_children():
		_meshes_under(child, into)


## Where a node sits relative to the model's root.
##
## Walked rather than read from `global_transform`, which means something else
## for a branch that is not in a tree — and this one never is.
static func _relative_to(root: Node, node: Node3D) -> Transform3D:
	var combined: Transform3D = Transform3D.IDENTITY
	var walk: Node = node

	while walk != null and walk != root:
		var spatial: Node3D = walk as Node3D
		if spatial != null:
			combined = spatial.transform * combined
		walk = walk.get_parent()

	return combined


## Copies one instance's surfaces into the target, moved into place and keeping
## the material each surface wears.
##
## Surface by surface rather than through `SurfaceTool`, which merges everything
## into one surface and so into one material. These models carry their colour in
## their materials and nothing else, so merging them would produce a palette of
## uniformly grey props.
static func _append(into: ArrayMesh, part: MeshInstance3D, at: Transform3D) -> void:
	var source: Mesh = part.mesh

	for surface: int in range(source.get_surface_count()):
		if source.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES:
			continue

		var arrays: Array = source.surface_get_arrays(surface)
		_move(arrays, at)
		into.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

		var slot: int = into.get_surface_count() - 1
		into.surface_set_material(slot, part.get_active_material(surface))
		into.surface_set_name(slot, "%s_%d" % [part.name, surface])


static func _move(arrays: Array, at: Transform3D) -> void:
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for index: int in range(vertices.size()):
		vertices[index] = at * vertices[index]
	arrays[Mesh.ARRAY_VERTEX] = vertices

	if arrays[Mesh.ARRAY_NORMAL] != null:
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for index: int in range(normals.size()):
			normals[index] = (at.basis * normals[index]).normalized()
		arrays[Mesh.ARRAY_NORMAL] = normals

	if arrays[Mesh.ARRAY_TANGENT] != null:
		# Four floats per vertex: a direction and the sign that says which way
		# the bitangent points. Only the direction moves.
		var tangents: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
		for index: int in range(0, tangents.size(), 4):
			var moved: Vector3 = (
				at.basis * Vector3(tangents[index], tangents[index + 1], tangents[index + 2])
			).normalized()
			tangents[index] = moved.x
			tangents[index + 1] = moved.y
			tangents[index + 2] = moved.z
		arrays[Mesh.ARRAY_TANGENT] = tangents


# --- the library itself ------------------------------------------------------


static func _existing(output: String) -> MeshLibrary:
	if not ResourceLoader.exists(output):
		return MeshLibrary.new()

	var library: MeshLibrary = ResourceLoader.load(
		output, "MeshLibrary", ResourceLoader.CACHE_MODE_IGNORE
	) as MeshLibrary
	return library if library != null else MeshLibrary.new()


## The thumbnails the palette shows.
##
## They are the difference between a usable palette and ninety identical grey
## squares, and they are also the reason this tool lives in the editor rather
## than in `tools/`: rendering a preview needs a renderer, and a headless script
## has none. One way to build a library, and it is the one that produces a
## complete one.
static func _bake_previews(library: MeshLibrary) -> void:
	if not Engine.is_editor_hint():
		return

	var ids: PackedInt32Array = library.get_item_list()
	var meshes: Array[Mesh] = []
	for id: int in ids:
		meshes.append(library.get_item_mesh(id))

	var previews: Array[Texture2D] = EditorInterface.make_mesh_previews(meshes, PREVIEW_SIZE)
	for index: int in range(mini(ids.size(), previews.size())):
		library.set_item_preview(ids[index], previews[index])


## Big enough to tell a fence from a cactus at a glance.
const PREVIEW_SIZE: int = 96


static func _index(library: MeshLibrary) -> Dictionary[String, int]:
	var by_name: Dictionary[String, int] = {}
	for id: int in library.get_item_list():
		by_name[library.get_item_name(id)] = id
	return by_name


## One past the highest id in use. Never a gap left by a removed item: reusing an
## id is the one thing that rewrites a painted map.
static func _next_id(library: MeshLibrary) -> int:
	var highest: int = -1
	for id: int in library.get_item_list():
		highest = maxi(highest, id)
	return highest + 1


# --- the look everything wears ------------------------------------------------


## Puts the printed look on every item, and the wind on the ones that are grass.
##
## Grass is picked by name, and by a fragment the author types rather than one
## written here. A rule guessed from the geometry would be a rule nobody could
## correct; a list in the dock is a decision somebody made and can see. With no
## fragment given, nothing is grass and everything is simply printed.
##
## One pass and not two, because `_imported` refuses to re-read a `ShaderMaterial`
## it cannot introspect: a second pass over an already-dressed surface would drop
## the colour on the floor rather than leaving it alone.
static func _dress_all(
	library: MeshLibrary, by_name: Dictionary[String, int], wanted: String, report: Report
) -> void:
	var comic: Shader = ResourceLoader.load(COMIC_SHADER, "Shader") as Shader
	if comic == null:
		report.problems.append("no shader at %s" % COMIC_SHADER)
		return

	var parting: Shader = null
	if not wanted.is_empty():
		parting = ResourceLoader.load(PARTING_SHADER, "Shader") as Shader
		if parting == null:
			report.problems.append("no shader at %s" % PARTING_SHADER)
			return

	report.look = CreatureView.roster_style()
	var look: Dictionary[String, Variant] = _look(report.look)
	var needle: String = wanted.to_lower()

	for item_name: String in by_name:
		var grass: bool = parting != null and item_name.to_lower().contains(needle)
		var shader: Shader = parting if grass else comic
		if not _dress(library.get_item_mesh(by_name[item_name]), shader, grass, look):
			continue
		if grass:
			report.parting.append(item_name)
		else:
			report.printed.append(item_name)


## The look the game is wearing, as values to push onto every surface.
##
## The same two files the creatures read — one style name, one preset table — so
## the world and a creature standing in it cannot end up wearing different looks.
##
## **These are baked into the library**, which is what makes switching looks a
## rebuild rather than a restart. The alternative is a runtime that walks every
## material in a loaded map and pushes the look, and that would be a second owner
## of the world's materials for a setting that changes once a month. Stated in the
## report so a library never lies about which look it is carrying.
##
## A style naming a shader rather than a comic preset — `toon`, `vinyl` — leaves
## this empty and the world on plain `comic`. The world has no toon shader, and
## silently dressing it in one it does not have is worse than not following.
static func _look(style: String) -> Dictionary[String, Variant]:
	var values: Dictionary[String, Variant] = CreatureView.preset_values(style)
	for name: String in WORLD_LOOK:
		values[name] = WORLD_LOOK[name]
	return values


## Replaces each surface's material with one that draws the same thing, printed.
##
## Returns whether anything was dressed, so an item that carried nothing swappable
## is not reported as done.
static func _dress(
	mesh: Mesh, shader: Shader, grass: bool, look: Dictionary[String, Variant]
) -> bool:
	if mesh == null:
		return false

	# The mesh's own extent, so the hinge is at this model's root and the tip
	# weight reaches one at this model's tip. One number guessed for every model
	# would put the bend in the wrong place on all but one of them — and the
	# grass here runs from 0.55 m to 3.4 m tall. Asked for only when it is grass:
	# nothing else has a blade.
	var box: AABB = mesh.get_aabb() if grass else AABB()

	var dressed: bool = false
	for surface: int in range(mesh.get_surface_count()):
		var material: ShaderMaterial = _imported(
			mesh.surface_get_material(surface), shader
		)
		if material == null:
			continue
		if grass:
			material.set_shader_parameter("blade_base", box.position.y)
			material.set_shader_parameter("blade_height", maxf(box.size.y, 0.05))
		# Before the look, not after: `_disown` puts everything this tool does not
		# own back to the shader's default, and the look is exactly the set of
		# values it is meant to then override.
		_disown(material, shader)
		for name: String in look:
			material.set_shader_parameter(name, look[name])
		mesh.surface_set_material(surface, material)
		dressed = true

	return dressed


## Puts every value this tool does not own back to the shader's own default.
##
## **A stored value outlives the shader that set it.** A material remembers what
## it was given, so tuning a number in the shader file changes nothing on a
## library saved before the change — the old value is still there and still wins.
## That cost an afternoon once: a wind tuned down to a fifth of its strength went
## on blowing at the old one, and the shader on disk was innocent.
static func _disown(material: ShaderMaterial, shader: Shader) -> void:
	for entry: Dictionary in shader.get_shader_uniform_list(true):
		var name: String = entry["name"]
		if not OWNED.has(name):
			# Null is how a `ShaderMaterial` is told to use the shader's default
			# rather than a value of its own.
			material.set_shader_parameter(name, null)


## Carries the imported material's colour across to the shader.
##
## These models have a flat colour and no texture at all, so this reproduces them
## exactly. A textured one is carried too — and anything richer than a colour and
## a texture is *not*, which is why an already-dressed surface is left alone
## rather than being re-read from a shader it cannot introspect.
##
## No flag says whether there is a texture: the shared look declares `albedo_tex`
## as `hint_default_white`, so an unset one multiplies by one and the colour comes
## through on its own. One less value that can disagree with itself.
static func _imported(existing: Material, shader: Shader) -> ShaderMaterial:
	if existing is ShaderMaterial:
		# Already dressed by an earlier run. Re-wrapping would lose the colour,
		# since a ShaderMaterial has no albedo to read back.
		return null

	var standard: StandardMaterial3D = existing as StandardMaterial3D
	var dressed: ShaderMaterial = ShaderMaterial.new()
	dressed.shader = shader

	if standard == null:
		return dressed

	dressed.set_shader_parameter("albedo", standard.albedo_color)
	if standard.albedo_texture != null:
		dressed.set_shader_parameter("albedo_tex", standard.albedo_texture)

	return dressed
