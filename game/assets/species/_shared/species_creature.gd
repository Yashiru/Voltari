@tool
extends Node3D

## Runtime wiring for an imported species creature.
##
## What a glTF cannot carry is reattached here: the cartoon shader and its ink
## outline, the scrolling flame, per-clip loop modes, the eye expressions, and
## which parts are stowed. One script covers every species — there is no
## per-model code.
##
## The expressions follow the AnimationPlayer's position, in the editor as well
## as in a running scene — scrubbing a clip in the Animation panel is the natural
## way to inspect one, and eyes that stayed frozen while the body moved read as a
## bug. What stays runtime-only is anything that would *write* to the scene: loop
## modes mutate the imported Animation resources, so they are not touched while
## editing.

## Where the shaders and this script live once installed in Voltari. Original
## work, so it ships — outside the species quarantine (Voltari decision 0046).
const SHARED: String = "res://game/presentation/creature/"

## Species-only assets that may never leave the quarantine (Voltari decision
## 0027): the flame textures are extracted from the source models and are not
## ours. A fakemon that wants a flame brings its own.
const SPECIES_SHARED: String = "res://game/assets/species/_shared/"

## The standalone viewer is a flat project and keeps everything at its root.
const SHARED_FLAT: String = "res://"

## Surface built by the export step to carry a face sheet. The part after the
## underscore names the block — `EyeOverlay_Eye`, `EyeOverlay_Mouth`.
const EYE_MATERIAL: String = "EyeOverlay"

## The look worn when nothing else says otherwise. The fallback, not the setting:
## `STYLE_FILE` overrides it when present, and a creature's own `style` overrides
## that. This is what a fresh checkout with no store file gets.
const DEFAULT_STYLE: String = "comic"

## Where the roster's look is recorded, beside the shaders. A file rather than
## this constant so the editor plugin can change it without editing source, and
## so switching costs no scene a save — which matters, because a style written
## into a `.tscn` stops following the roster for good.
const STYLE_FILE: String = "style.txt"

## The value of `style` that means "whatever the roster is wearing".
const STYLE_ROSTER: String = "roster"

## The shading curve `ramp.gdshader` reads, if one is installed beside the
## shaders. Absent, that shader falls back to plain lighting rather than black.
const RAMP_FILE: String = "shading_ramp.png"

## Named settings of a shader, offered in the style menu as looks in their own
## right — `comic-noir` is `comic.gdshader` with a different set of numbers.
##
## Data rather than code, and that is the whole point: five variations of a look
## are five sets of values, and duplicating the shader to hold them would mean
## fixing every bug in it five times over.
const PRESET_FILE: String = "style_presets.json"

## What each element looks like, for `typelit.gdshader`.
##
## The seventeen names are the project's own — `content/type-chart.yaml`, Gen 4
## without Fairy, decision 0003 — so nothing here invents a vocabulary. The
## colours themselves are provisional: they are a first reading, not an art
## direction, and the day one exists this table is where it lands.
const TYPE_COLOURS: Dictionary[String, Color] = {
	"neutral": Color(0.72, 0.75, 0.82),
	"bug": Color(0.65, 0.75, 0.24),
	"dark": Color(0.42, 0.35, 0.32),
	"dragon": Color(0.44, 0.36, 0.95),
	"electric": Color(0.99, 0.82, 0.20),
	"fighting": Color(0.76, 0.30, 0.24),
	"fire": Color(0.98, 0.50, 0.20),
	"flying": Color(0.66, 0.72, 0.95),
	"ghost": Color(0.45, 0.38, 0.62),
	"grass": Color(0.48, 0.78, 0.35),
	"ground": Color(0.88, 0.75, 0.42),
	"ice": Color(0.60, 0.88, 0.90),
	"normal": Color(0.78, 0.76, 0.68),
	"poison": Color(0.68, 0.36, 0.68),
	"psychic": Color(0.98, 0.44, 0.60),
	"rock": Color(0.72, 0.64, 0.34),
	"steel": Color(0.72, 0.75, 0.80),
	"water": Color(0.32, 0.62, 0.95),
}

## The eye atlas is two columns of four rows, and the driver's state numbers walk
## it a column at a time: state 4 is the top of the second column, not a fifth
## row. Stepping only downwards made states 4-7 wrap back onto 0-3, so a clip
## holding state 4 for a second showed the idle eye and changed nothing — which
## is not something an animator would key.
const EYE_ROW_V: float = 0.25
const EYE_COLUMN_U: float = 0.5
const EYE_ROWS: int = 4

## Idle clips loop; everything else plays once. Matched as a substring because
## take naming is not consistent across models — pm0006 has `waitA01`, pm0001
## has `ba10_waitA01`. An exact list silently matched nothing on the second
## model exported.
const LOOPING_MARKER: String = "wait"

## Share of the highlight the eye surfaces keep. The drawing already has one.
const EYE_HIGHLIGHT: float = 0.25

signal animation_finished(clip: String)


## One animated region of a face. A creature does not have a single expression
## surface: Pikachu has three — the eyes on page 1 of its face sheet, the mouth
## on page 2, and the cheeks on a 128x512 strip of their own — and each follows
## its own driver. Sharing one offset between them walked the mouth every time
## the eyes blinked and put an eye on the cheek.
class FaceBlock:
	## Surfaces carrying this block. Usually one, several when the block spans
	## more than one mesh.
	var surfaces: Array[ShaderMaterial] = []
	## Width of one column of this block's sheet, in UV.
	var column_u: float = 0.5
	## Clip name -> flat [time, state, time, state, …], held stepwise.
	var clips: Dictionary[String, PackedFloat32Array] = {}
	## Cell currently shown, or -1 before the first frame.
	var state: int = -1

## The look, exposed here rather than left inside the shader: the materials are
## built at runtime, so they never appear in the inspector and the shader's own
## sliders are unreachable. Editing these on the scene root updates the creature
## live, because the script is @tool.
@export_group("Look")
## Which surface shader this creature wears, without the extension. `roster`
## follows whatever the whole set is wearing and is what every species ships
## with; naming a shader here pins this one creature to it and it stops following
## the set. All the shaders live side by side in `_shared/` and none is removed
## when another is added — comparing them on the same creature is the only way to
## judge one.
@export_enum("roster", "comic", "comic-clear", "comic-manga", "comic-noir",
	"comic-newsprint", "comic-sunday", "toon", "bd", "vinyl", "ramp", "typelit")
var style: String = STYLE_ROSTER:
	set(value):
		style = value
		if is_inside_tree():
			_rebuild_look()
## The creature's element, for the looks that carry one — `typelit` edges the
## silhouette with it and tints the shadow towards it. Ignored by every other
## shader, which simply has no such parameter.
##
## Set by hand for now. These are species named after dex numbers, and the
## project's own `content/species/` holds three species species, so there is
## nothing yet to read a real type from.
## Wear the second colouring, when the model ships one.
##
## Same GLB, same rig, same expression blocks — only the sheets change. The
## textures sit in a `shiny/` folder beside the scene, one per surface, and the
## clip data says which belongs to which. A model with none simply ignores this.
@export var shiny: bool = false:
	set(value):
		shiny = value
		if is_inside_tree():
			_rebuild_look()
@export_enum("neutral", "bug", "dark", "dragon", "electric", "fighting", "fire",
	"flying", "ghost", "grass", "ground", "ice", "normal", "poison", "psychic",
	"rock", "steel", "water")
var accent_type: String = "neutral":
	set(value):
		accent_type = value
		_push_look()
@export_range(0.5, 2.5) var saturation: float = 1.35:
	set(value):
		saturation = value
		_push_look()
@export_range(1.0, 6.0) var light_bands: float = 3.0:
	set(value):
		light_bands = value
		_push_look()
@export_range(0.0, 3.0) var crease_strength: float = 1.15:
	set(value):
		crease_strength = value
		_push_look()
@export_range(0.0, 2.0) var rim_strength: float = 0.55:
	set(value):
		rim_strength = value
		_push_look()
@export_range(0.0, 2.0) var highlight: float = 0.35:
	set(value):
		highlight = value
		_push_look()
## How much the highlight gives way on an already-bright surface. At 0 a fixed
## white blob blows out the dark creatures and stains the pale ones.
@export_range(0.0, 1.0) var highlight_adapt: float = 0.65:
	set(value):
		highlight_adapt = value
		_push_look()
@export_range(0.0, 8.0) var outline_thickness: float = 1.8:
	set(value):
		outline_thickness = value
		_push_look()
@export_group("")

## Where to read the per-clip data from. Left empty it is derived from the scene
## file, which is how an installed species works. The standalone viewer
## instantiates a bare GLB, which has no scene file, so it sets this.
var clip_data_path: String = ""

## Atlas cell the eyes are currently showing, or -1 before the first frame.
var eye_state: int = -1

var _player: AnimationPlayer = null
var _clips: PackedStringArray = PackedStringArray()
var _eye_materials: Array[ShaderMaterial] = []

## The clip file as parsed, held so the surfaces can be built between reading it
## and attaching the face blocks to them.
var _clip_data: Dictionary = {}

## Surface name -> the file holding its second colouring, empty when the model
## ships only one.
var _shiny: Dictionary[String, String] = {}

## Block name -> its surfaces, sheet geometry and timeline.
var _blocks: Dictionary[String, FaceBlock] = {}

## Block name each entry of `_eye_materials` belongs to, same order. Filled while
## walking the surfaces, before the clip data that describes the blocks is read.
var _eye_labels: PackedStringArray = PackedStringArray()

## Every surface carrying the cartoon shader, so the look can be pushed to all
## of them at once.
var _surfaces: Array[ShaderMaterial] = []

## Clip name -> flat [time, state, time, state, …], held stepwise. The primary
## block's timeline, kept for a species exported before blocks existed.
var _eye_clips: Dictionary[String, PackedFloat32Array] = {}

## The preset the current style resolves to, empty when the style names a shader
## directly. Held rather than looked up twice: `_push_look` has to re-apply it
## after the sliders, and re-reading the file on every slider drag would parse
## JSON once per frame while one is being dragged.
var _preset: Dictionary = {}

## Column width for this model's atlas. A constant was right only for the
## 256-wide atlases; Pikachu's is 512 and carries mouths in its right half.
var _eye_column_u: float = EYE_COLUMN_U

## Meshes that fold away when unused — Bulbasaur's vines are their own objects,
## stowed to a stub for eight of nine clips. Left visible they hang off the
## model as stray filaments.
var _stowable: Array[MeshInstance3D] = []

## Clip name -> flat [on, off, on, off, …] in seconds. A clip with no entry
## keeps its stowable parts hidden throughout.
var _part_clips: Dictionary[String, PackedFloat32Array] = {}


func _ready() -> void:
	# @tool so the flame and the eyes show in the editor viewport too — without
	# it the baked fallback is all you see until you run the scene.
	_rebuild_look()
	_player = _find_player(self)
	if _player != null:
		_clips = _player.get_animation_list()
		_clips.sort()

	# Everything below changes state the editor would then offer to save. Loop
	# modes in particular are written onto the imported Animation resources.
	if not Engine.is_editor_hint() and _player != null:
		_set_loop_modes()
		_player.animation_finished.connect(func(name: String) -> void:
			animation_finished.emit(name))
		if not _clips.is_empty():
			play(_clips[0])

	var expressive: bool = false
	for block: FaceBlock in _blocks.values():
		if not block.clips.is_empty() and not block.surfaces.is_empty():
			expressive = true
			break
	set_process(expressive or not _stowable.is_empty())


## The expression is a discrete state, so it is looked up and held rather than
## interpolated: a value between two rows would sample across two drawings and
## slice the eye in half.
##
## Driven by the playhead rather than by `is_playing()`, so that dragging through
## a clip in the editor moves the eyes with the body. A paused or scrubbed player
## reports a position but not that it is playing.
func _process(_delta: float) -> void:
	if _player == null:
		return
	# `current_animation` empties the moment playback pauses or stops, while
	# `assigned_animation` keeps the name and the position stays valid. Reading
	# the former is why scrubbing left the eyes behind.
	var clip: String = _player.assigned_animation
	if clip.is_empty():
		clip = _player.current_animation
	var now: float = _player.current_animation_position

	var primary: bool = true
	for name: String in _blocks:
		var block: FaceBlock = _blocks[name]
		_set_block_state(block, _state_at(block.clips, clip, now))
		if primary:
			eye_state = block.state
			primary = false

	# Runs for every clip, not only the ones with expressions: the clips with
	# nothing to say about the eyes are exactly the ones where a vine has to
	# stay stowed.
	_set_parts(clip, now)


## The colour of this creature's element, neutral grey when it has none or when
## the name is one the palette does not know.
func _accent() -> Color:
	if TYPE_COLOURS.has(accent_type):
		return TYPE_COLOURS[accent_type]
	return TYPE_COLOURS["neutral"]


## Every named preset, or an empty map when none is installed.
static func presets() -> Dictionary:
	for base: String in [SHARED, SPECIES_SHARED, SHARED_FLAT]:
		var path: String = base + PRESET_FILE
		if not FileAccess.file_exists(path):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		@warning_ignore("unsafe_cast")
		return parsed as Dictionary
	return {}


## Push a preset's uniforms onto one surface.
##
## Read by JSON type: a number is a float, a `#rrggbb` string a colour. Anything
## else is skipped, so a typo in the file leaves the shader on its own defaults
## rather than producing a creature that quietly looks wrong.
##
## Applied after the inspector's sliders, so the preset wins. A preset is a
## deliberate statement about a look, and a slider left at its default is not a
## good reason to half-undo it — which does mean the `saturation` slider does
## nothing on a preset that names its own.
func _apply_preset(material: ShaderMaterial) -> void:
	var values: Variant = _preset.get("uniforms")
	if typeof(values) != TYPE_DICTIONARY:
		return
	@warning_ignore("unsafe_cast")
	var table: Dictionary = values as Dictionary
	for key: Variant in table:
		var value: Variant = table[key]
		var kind: int = typeof(value)
		if kind == TYPE_FLOAT or kind == TYPE_INT:
			material.set_shader_parameter(str(key), value)
		elif kind == TYPE_STRING:
			material.set_shader_parameter(str(key), Color.html(str(value)))


## The look the whole set is wearing, from the store beside the shaders.
##
## Static so a tool that has no creature to hand — the editor plugin — can read
## the same answer from the same place rather than keeping its own copy.
static func roster_style() -> String:
	for base: String in [SHARED, SPECIES_SHARED, SHARED_FLAT]:
		var path: String = base + STYLE_FILE
		if not FileAccess.file_exists(path):
			continue
		var wanted: String = FileAccess.get_file_as_string(path).strip_edges()
		if not wanted.is_empty():
			return wanted
	return DEFAULT_STYLE


## The texture a surface should wear: the one baked into the GLB, or its second
## colouring when this creature is shiny and the model ships one.
##
## Keyed on the surface's own name, because by export time a source file and a
## surface no longer line up — the eye sheets are copied opaque and several
## surfaces can share one file. The export writes one texture per surface for
## exactly that reason.
func _albedo_for(surface: String, baked: Texture2D) -> Texture2D:
	if not shiny or not _shiny.has(surface):
		return baked
	var path: String = _shiny_dir() + _shiny[surface]
	if not ResourceLoader.exists(path):
		push_warning("no shiny texture at %s" % path)
		return baked
	var wearing: Texture2D = load(path) as Texture2D
	return wearing if wearing != null else baked


## Where this creature's second colouring lives, beside its scene.
func _shiny_dir() -> String:
	var base: String = clip_data_path.get_base_dir()
	if base.is_empty() and not scene_file_path.is_empty():
		base = scene_file_path.get_base_dir()
	# path_join rather than a glued slash: the viewer's clip path sits at the
	# project root, whose base directory is already `res://`, and gluing gives
	# `res:///shiny/`.
	return base.path_join("shiny") + "/"


## Rebuild the surfaces after something outside this node changed the look.
## Called by the editor plugin when the roster's style is switched; a creature
## pinned to its own style is rebuilt too and simply comes back the same.
func refresh_look() -> void:
	_rebuild_look()


## Rebuild every surface and reattach the face blocks to it.
##
## The three run together because the blocks hold the materials: swapping the
## shader makes new ones, and a block still pointing at the old set would leave
## the eyes frozen on whichever cell they were built at.
func _rebuild_look() -> void:
	# Read before building: which texture a surface wears depends on the shiny
	# map, and that lives in the clip file. Attach after: a face block holds the
	# materials, which do not exist until the surfaces are built.
	_load_clip_data()
	_apply_shaders()
	_push_look()
	_read_blocks(_clip_data.get("eyes"))


## Send the exposed look to every surface. Called on load and whenever one of
## the exported values changes, so the inspector edits show immediately.
func _push_look() -> void:
	for material: ShaderMaterial in _surfaces:
		material.set_shader_parameter("saturation", saturation)
		material.set_shader_parameter("bands", light_bands)
		material.set_shader_parameter("crease_strength", crease_strength)
		material.set_shader_parameter("rim_strength", rim_strength)
		material.set_shader_parameter("spec_adapt", highlight_adapt)
		# The eye artwork is painted with its own glint. A second highlight on
		# top of it reads as a smear, so those surfaces get a fraction.
		var face: bool = _eye_materials.has(material)
		var share: float = EYE_HIGHLIGHT if face else 1.0
		material.set_shader_parameter("spec_strength", highlight * share)
		# Same reasoning one step further for the printed look: a face sheet is
		# already a drawing, and laying screentone over it fills the whites of
		# the eyes with dots. A shader with no such parameter ignores this.
		material.set_shader_parameter("face_flat", 1.0 if face else 0.0)
		material.set_shader_parameter("accent", _accent())
		var ink: Material = material.next_pass
		if ink is ShaderMaterial:
			(ink as ShaderMaterial).set_shader_parameter("thickness", outline_thickness)
		# Last, so a named look is not half-undone by a slider sitting at its
		# default. See `_apply_preset`.
		_apply_preset(material)


## A stowable part is out only inside one of its clip's windows.
func _set_parts(clip: String, now: float) -> void:
	if _stowable.is_empty():
		return
	var out: bool = false
	if _part_clips.has(clip):
		var windows: PackedFloat32Array = _part_clips[clip]
		var i: int = 0
		while i + 1 < windows.size():
			if now >= windows[i] and now < windows[i + 1]:
				out = true
				break
			i += 2
	for part: MeshInstance3D in _stowable:
		if part.visible != out:
			part.visible = out


## The state a timeline holds at `now`, or 0 for a clip it says nothing about.
func _state_at(by_clip: Dictionary[String, PackedFloat32Array], clip: String,
		now: float) -> int:
	if not by_clip.has(clip):
		return 0
	var timeline: PackedFloat32Array = by_clip[clip]
	var state: int = 0
	var i: int = 0
	while i + 1 < timeline.size():
		if timeline[i] > now:
			break
		state = int(timeline[i + 1])
		i += 2
	return state


func _set_block_state(block: FaceBlock, state: int) -> void:
	if state == block.state:
		return
	block.state = state
	# Wrapped into the sheet rather than left to the shader's fract(). pm0081 has
	# a single column and one clip that drives the state to 70; the offset landed
	# seventeen sheet widths away and only came back because the sampler wraps.
	# Relying on that made the cell an accident of the shader rather than a
	# decision here, and posmod keeps a negative state defined too.
	var cells: int = maxi(roundi(1.0 / block.column_u), 1) * EYE_ROWS
	var cell: int = posmod(state, cells)
	@warning_ignore("integer_division")
	var column: int = cell / EYE_ROWS
	var row: int = cell % EYE_ROWS
	var offset: Vector2 = Vector2(float(column) * block.column_u, -float(row) * EYE_ROW_V)
	for material: ShaderMaterial in block.surfaces:
		material.set_shader_parameter("uv_offset", offset)


## Available clip names, sorted.
func clips() -> PackedStringArray:
	return _clips


func play(clip: String) -> void:
	if _player != null and _player.has_animation(clip):
		_player.play(clip)


func _set_loop_modes() -> void:
	for clip: String in _clips:
		var anim: Animation = _player.get_animation(clip)
		if anim == null:
			continue
		anim.loop_mode = (Animation.LOOP_LINEAR
			if clip.to_lower().contains(LOOPING_MARKER)
			else Animation.LOOP_NONE)


func _find_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null


## Every surface in one walk: the flame keeps its scrolling shader, everything
## else gets the cartoon shader, and the eye surfaces are kept aside so their
## atlas cell can be moved later.
##
## The ink outline goes on the body only. The eye decal is head geometry moved
## onto its own material, so an outline shell around it would draw a line around
## the eye patch rather than around the creature.
func _apply_shaders() -> void:
	_eye_materials.clear()
	_eye_labels.clear()
	_surfaces.clear()
	# Named rather than fixed, so a look can be swapped on one creature without
	# touching any other. An unknown name falls back rather than leaving the
	# creature untextured, because a typo in the inspector should not look like a
	# broken export.
	var wanted: String = style
	if wanted.is_empty() or wanted == STYLE_ROSTER:
		wanted = roster_style()

	# A style names either a shader or a preset of one. Presets are looked up
	# first so a name can never mean two things at once.
	_preset = {}
	var named: Variant = presets().get(wanted)
	if typeof(named) == TYPE_DICTIONARY:
		@warning_ignore("unsafe_cast")
		_preset = named as Dictionary
		var base: Variant = _preset.get("shader")
		if typeof(base) == TYPE_STRING:
			wanted = str(base)

	var toon: Shader = _shared_load(wanted + ".gdshader") as Shader
	if toon == null and wanted != DEFAULT_STYLE:
		push_warning("no shader called %s.gdshader — falling back to %s"
			% [wanted, DEFAULT_STYLE])
		toon = _shared_load(DEFAULT_STYLE + ".gdshader") as Shader
	var outline: Shader = _shared_load("outline.gdshader") as Shader
	if toon == null:
		return

	var ink: ShaderMaterial = null
	if outline != null:
		ink = ShaderMaterial.new()
		ink.shader = outline

	# The shading curve `ramp.gdshader` reads. Bound to every surface rather than
	# only to that one: a material carrying a parameter no shader declares simply
	# ignores it, and testing which shader is in use here would be a second place
	# that has to learn about a third.
	var ramp: Texture2D = _shared_load(RAMP_FILE) as Texture2D

	var flame: Shader = _shared_load("flame.gdshader") as Shader
	var core: Texture2D = _shared_load("FireCoreCombo.png") as Texture2D
	var sten: Texture2D = _shared_load("FireStenCombo.png") as Texture2D
	var core_mat: ShaderMaterial = null
	var sten_mat: ShaderMaterial = null
	if flame != null and core != null and sten != null:
		core_mat = _flame_material(flame, core, sten, 0)
		sten_mat = _flame_material(flame, core, sten, 1)

	for node: Node in _descendants(self):
		if not (node is MeshInstance3D):
			continue
		var instance: MeshInstance3D = node as MeshInstance3D
		var mesh: Mesh = instance.mesh
		if mesh == null:
			continue
		for i: int in range(mesh.get_surface_count()):
			var existing: Material = mesh.surface_get_material(i)
			if existing == null:
				continue
			var label: String = existing.resource_name

			if label.begins_with("FireCore") and core_mat != null:
				instance.set_surface_override_material(i, core_mat)
				continue
			if label.begins_with("FireSten") and sten_mat != null:
				instance.set_surface_override_material(i, sten_mat)
				continue
			if not (existing is BaseMaterial3D):
				continue

			var source: BaseMaterial3D = existing as BaseMaterial3D
			var material: ShaderMaterial = ShaderMaterial.new()
			material.shader = toon
			material.set_shader_parameter("albedo_tex",
				_albedo_for(label, source.albedo_texture))
			material.set_shader_parameter("uv_offset", Vector2.ZERO)
			if ramp != null:
				material.set_shader_parameter("shading_ramp", ramp)
			var is_eye: bool = label.begins_with(EYE_MATERIAL)
			if not is_eye:
				material.next_pass = ink
			# The mesh's own centre, for the rounded shading normal. Left in
			# local space so it follows the node without being pushed again.
			# A shader with no such parameter ignores it.
			material.set_shader_parameter("shape_centre",
				mesh.get_aabb().get_center())
			instance.set_surface_override_material(i, material)
			_surfaces.append(material)
			if is_eye:
				_eye_materials.append(material)
				# `EyeOverlay_Mouth` -> `Mouth`. A surface exported before blocks
				# existed is called `EyeOverlay` flat and gives an empty name,
				# which the clip data answers with its own default block.
				_eye_labels.append(label.substr(EYE_MATERIAL.length() + 1))


## Written beside the model by the export step: when each clip changes
## expression, and when a stowable part is out. Absent for models with neither.
func _load_clip_data() -> void:
	_eye_clips = {}
	_part_clips = {}
	_stowable = []
	_shiny = {}
	_clip_data = {}

	# Derived from the scene file, not from `name`: a node renamed on instancing
	# would otherwise silently lose its expressions.
	var path: String = clip_data_path
	if path.is_empty():
		if scene_file_path.is_empty():
			return
		var stem: String = scene_file_path.get_file().get_basename()
		path = scene_file_path.get_base_dir() + "/" + stem + ".clips.json"
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	# JSON has no types to preserve, so the casts out of Variant are unchecked by
	# definition. They are confined to this function and each is guarded by a
	# typeof() first.
	@warning_ignore("unsafe_cast")
	var data: Dictionary = parsed as Dictionary
	_clip_data = data

	var wearing: Variant = data.get("shiny")
	if typeof(wearing) == TYPE_DICTIONARY:
		@warning_ignore("unsafe_cast")
		var by_surface: Dictionary = wearing as Dictionary
		for surface: Variant in by_surface:
			_shiny[str(surface)] = str(by_surface[surface])

	_eye_clips = _timelines(data.get("eyes"))
	_eye_column_u = _column_u(data.get("eyes"))
	var parts: Variant = data.get("parts")
	if typeof(parts) != TYPE_DICTIONARY:
		return
	@warning_ignore("unsafe_cast")
	var parts_data: Dictionary = parts as Dictionary
	_part_clips = _timelines(parts_data)

	var named: Variant = parts_data.get("parts")
	if typeof(named) != TYPE_ARRAY:
		return
	@warning_ignore("unsafe_cast")
	var wanted: Array = named as Array
	for node: Node in _descendants(self):
		if node is MeshInstance3D and wanted.has(node.name):
			_stowable.append(node as MeshInstance3D)


## Build one FaceBlock per entry of the clip data's `blocks` map and hand each
## the surfaces that carry it.
##
## A species exported before blocks existed has no such map and a single
## surface called `EyeOverlay`. That case is not special-cased: it becomes one
## block holding every overlay surface, on the flat `clips` and `column_u` — the
## same shape the whole library had until the sheets were read properly.
func _read_blocks(section: Variant) -> void:
	_blocks = {}
	var described: Dictionary = {}
	if typeof(section) == TYPE_DICTIONARY:
		@warning_ignore("unsafe_cast")
		var holder: Dictionary = section as Dictionary
		var raw: Variant = holder.get("blocks")
		if typeof(raw) == TYPE_DICTIONARY:
			@warning_ignore("unsafe_cast")
			described = raw as Dictionary

	for key: Variant in described:
		var entry: Variant = described[key]
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var block: FaceBlock = FaceBlock.new()
		block.column_u = _column_u(entry)
		block.clips = _timelines(entry)
		_blocks[str(key)] = block

	if _blocks.is_empty():
		var fallback: FaceBlock = FaceBlock.new()
		fallback.column_u = _eye_column_u
		fallback.clips = _eye_clips
		_blocks[""] = fallback

	for i: int in range(_eye_materials.size()):
		var name: String = _eye_labels[i] if i < _eye_labels.size() else ""
		# An unnamed surface, or one whose block the clip data does not describe,
		# still has to be driven by something: it joins the first block rather
		# than freezing on whatever cell it was exported at.
		if not _blocks.has(name):
			name = _blocks.keys()[0]
		_blocks[name].surfaces.append(_eye_materials[i])


## The `clips` map of a section, as packed float arrays.
## Width of one atlas column, measured at export from the atlas itself.
func _column_u(section: Variant) -> float:
	if typeof(section) != TYPE_DICTIONARY:
		return EYE_COLUMN_U
	@warning_ignore("unsafe_cast")
	var holder: Dictionary = section as Dictionary
	var value: Variant = holder.get("column_u")
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return EYE_COLUMN_U
	@warning_ignore("unsafe_cast")
	var width: float = value as float
	return width if width > 0.0 else EYE_COLUMN_U


func _timelines(section: Variant) -> Dictionary[String, PackedFloat32Array]:
	var out: Dictionary[String, PackedFloat32Array] = {}
	if typeof(section) != TYPE_DICTIONARY:
		return out
	@warning_ignore("unsafe_cast")
	var holder: Dictionary = section as Dictionary
	var raw: Variant = holder.get("clips")
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	@warning_ignore("unsafe_cast")
	var by_clip: Dictionary = raw as Dictionary
	for key: Variant in by_clip:
		var entries: Variant = by_clip[key]
		if typeof(entries) != TYPE_ARRAY:
			continue
		# Part windows arrive as nested [on, off] pairs; expressions arrive flat.
		var flat: Array = []
		@warning_ignore("unsafe_cast")
		for item: Variant in entries as Array:
			if typeof(item) == TYPE_ARRAY:
				@warning_ignore("unsafe_cast")
				flat.append_array(item as Array)
			else:
				flat.append(item)
		@warning_ignore("unsafe_call_argument")
		var timeline := PackedFloat32Array(flat)
		if not timeline.is_empty():
			out[str(key)] = timeline
	return out


func _flame_material(shader: Shader, core: Texture2D, sten: Texture2D,
		layer: int) -> ShaderMaterial:
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("core_tex", core)
	mat.set_shader_parameter("sten_tex", sten)
	mat.set_shader_parameter("layer", layer)
	return mat


## Shared assets sit under _shared/ once installed and at the project root in
## the standalone viewer. Loading a missing path prints an error, so existence
## is checked first rather than letting the first attempt fail noisily.
func _shared_load(file: String) -> Resource:
	for base: String in [SHARED, SPECIES_SHARED, SHARED_FLAT]:
		if ResourceLoader.exists(base + file):
			return load(base + file)
	return null


func _descendants(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child: Node in node.get_children():
		found.append_array(_descendants(child))
	return found
