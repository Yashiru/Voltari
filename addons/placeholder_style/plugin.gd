@tool
extends EditorPlugin

## The look control: which look the game wears, and a panel to push it around.
##
## **The picker used to do nothing**, and the reason was one line: it wrote the
## chosen name to `game/assets/placeholders/_shared/style.txt` while the runtime
## read `game/presentation/creature/style.txt`. Two files, two values, and a
## control that looked like it worked. It writes where the game reads now, through
## `Look.choose`, so there is one path and no way for them to drift again.
##
## Two halves, both in the 3D toolbar's dock:
##
## - **the picker**, which names the look everything wears
## - **the sliders**, which push one value onto every material in the open scene
##   as they move, so a number can be found by looking rather than by guessing
##
## A slider is a *trial*. Nothing it does is written anywhere: shut the editor and
## the look is whatever the picker last chose. **Keep** copies the current trial
## into `style_presets.json` under the chosen name, which is what makes it stick
## and what makes the creatures follow — they read the same file.
##
## ## What it can and cannot reach
##
## It dresses the **open scene**. A map scene is full of `GridMap` cells and
## restyles completely; the world sandbox builds its map in code, so there is
## nothing in it to dress until the game runs — which is why the world applies the
## chosen look for itself on load. The count under the picker says which case you
## are in rather than pretending.
##
## The addon is still called `placeholder_style` because its folder is named in
## `project.godot`, and that file carries the maintainer's editor state. The name
## is a wart, not a scope.

## Looks offered, in order. A comic preset restyles the whole game; the others are
## separate creature shaders and the world has no variant of them, so picking one
## leaves the world on plain `comic` rather than dressing it in a shader that does
## not exist.
const LOOKS: PackedStringArray = ["comic", "comic-clear", "comic-manga", "comic-noir",
	"comic-newsprint", "comic-sunday", "toon", "bd", "vinyl", "ramp", "typelit"]

## What the sliders offer, grouped the way the shader groups them.
##
## A curated list, not every uniform. Forty sliders is a wall nobody reads; these
## are the ones that change what the look *is* rather than trimming it. The rest
## stay in the shader's own defaults, where art direction lives.
const KNOBS: Array = [
	["light", "terminator", -0.6, 0.6],
	["light", "core_level", -1.0, 0.2],
	["light", "ink", 0.3, 1.0],
	["paint", "saturation", 0.5, 2.0],
	["paint", "lift", 0.0, 0.3],
	["shadow", "shadow_depth", 0.0, 0.9],
	["shadow", "shadow_hue_mix", 0.0, 1.0],
	["shadow", "core_extra", 0.0, 0.6],
	["cast", "cast_hardness", 0.0, 1.0],
	["cast", "cast_screen", 0.0, 1.2],
	["cast", "cast_line", 0.0, 0.8],
	["screen", "dots_amount", 0.0, 1.0],
	["screen", "dots_size", 3.0, 24.0],
	["screen", "dots_darken", 0.0, 0.7],
	["ink line", "edge_line", 0.0, 0.8],
	["ink line", "chatter_amount", 0.0, 0.15],
	["ground", "grain_amount", 0.0, 0.6],
	["ground", "contact_shade", 0.0, 0.8],
]

var _panel: VBoxContainer = null
var _picker: OptionButton = null
var _reach: Label = null
var _sliders: Dictionary[String, HSlider] = {}
var _trial: Dictionary[String, Variant] = {}


func _enter_tree() -> void:
	_panel = VBoxContainer.new()
	_panel.name = "Look"

	_picker = OptionButton.new()
	_picker.tooltip_text = ("The look the whole game wears.\n"
		+ "Written to style.txt, which is what the game reads on load.")
	for name: String in LOOKS:
		_picker.add_item(name)
	_picker.select(maxi(LOOKS.find(Look.chosen()), 0))
	@warning_ignore("return_value_discarded")
	_picker.item_selected.connect(_choose)
	_panel.add_child(_picker)

	_reach = Label.new()
	_reach.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_reach)

	var group: String = ""
	for knob: Array in KNOBS:
		if str(knob[0]) != group:
			group = str(knob[0])
			var heading: Label = Label.new()
			heading.text = group
			_panel.add_child(heading)
		_panel.add_child(_knob(str(knob[1]), float(knob[2]), float(knob[3])))

	var keep: Button = Button.new()
	keep.text = "Keep as " + LOOKS[_picker.selected]
	keep.tooltip_text = ("Write the sliders into style_presets.json under this "
		+ "name. Until you do, they are a trial and nothing outside this editor "
		+ "session sees them.")
	@warning_ignore("return_value_discarded")
	keep.pressed.connect(_keep)
	_panel.add_child(keep)

	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _panel)
	_show_reach()


func _exit_tree() -> void:
	if _panel == null:
		return
	remove_control_from_docks(_panel)
	_panel.queue_free()
	_panel = null
	_picker = null
	_reach = null
	_sliders.clear()


## One labelled slider, reading the look's current value for its starting point.
func _knob(name: String, low: float, high: float) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	var label: Label = Label.new()
	label.text = name
	row.add_child(label)

	var slider: HSlider = HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = (high - low) / 200.0
	slider.value = _starting(name, low, high)
	slider.tooltip_text = name
	@warning_ignore("return_value_discarded")
	slider.value_changed.connect(_pushed.bind(name, label))
	row.add_child(slider)

	_sliders[name] = slider
	label.text = "%s  %.3f" % [name, slider.value]
	return row


## Where a slider starts: the chosen look's value for it, or the middle of its
## range when the look says nothing. Reading the shader's own default would be
## better and there is no way to ask for one without a material to hand.
func _starting(name: String, low: float, high: float) -> float:
	var values: Dictionary[String, Variant] = CreatureView.preset_values(
		LOOKS[_picker.selected]
	)
	if values.has(name) and typeof(values[name]) != TYPE_COLOR:
		return clampf(float(values[name]), low, high)
	return (low + high) * 0.5


func _pushed(value: float, name: String, label: Label) -> void:
	label.text = "%s  %.3f" % [name, value]
	_trial[name] = value
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return
	@warning_ignore("return_value_discarded")
	Look.tune(root, name, value)
	_show_reach()


func _choose(index: int) -> void:
	if index < 0 or index >= LOOKS.size():
		return
	var wanted: String = LOOKS[index]
	var wrote: Error = Look.choose(wanted)
	if wrote != OK:
		push_warning("cannot record the look: %s" % error_string(wrote))
		return

	_trial.clear()
	for name: String in _sliders:
		var slider: HSlider = _sliders[name]
		slider.set_block_signals(true)
		slider.value = _starting(name, slider.min_value, slider.max_value)
		slider.set_block_signals(false)

	var root: Node = EditorInterface.get_edited_scene_root()
	if root != null:
		@warning_ignore("return_value_discarded")
		Look.wear(root, wanted)
		# A creature holds its own materials and rebuilds them rather than being
		# written to, so it is asked rather than dressed.
		_ask_creatures(root)
	_show_reach()


## Writes the trial into the preset file, under the chosen name.
##
## Merged rather than replaced: a preset carries values no slider offers, and a
## Keep that dropped them would quietly rewrite a look instead of adjusting it.
func _keep() -> void:
	if _trial.is_empty():
		push_warning("nothing to keep — no slider has been moved")
		return
	var wanted: String = LOOKS[_picker.selected]
	var presets: Dictionary = CreatureView.presets()
	if not presets.has(wanted):
		push_warning("%s is a shader, not a preset — nothing to write to" % wanted)
		return

	@warning_ignore("unsafe_cast")
	var entry: Dictionary = presets[wanted] as Dictionary
	var uniforms: Variant = entry.get("uniforms")
	if typeof(uniforms) != TYPE_DICTIONARY:
		push_warning("%s has no uniforms to write to" % wanted)
		return
	@warning_ignore("unsafe_cast")
	var fields: Dictionary = uniforms as Dictionary
	for name: String in _trial:
		fields[name] = _trial[name]

	var path: String = CreatureView.SHARED + CreatureView.PRESET_FILE
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("cannot write %s: %s"
			% [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(presets, "\t"))
	file.close()
	_trial.clear()
	print("look: kept %s" % wanted)


## Says what the panel is actually reaching, rather than implying it reached
## everything. Zero is the honest and common answer: a scene that builds its world
## at run time has nothing to dress until it runs.
func _show_reach() -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		_reach.text = "no scene open — nothing to push onto"
		return
	var worn: int = Look.worn_under(root).size()
	if worn == 0:
		_reach.text = ("%s: nothing wearing the look. A map scene restyles here; "
			+ "a scene that builds its world in code only changes when you run it."
			) % root.name
		return
	_reach.text = "%s: %d material(s)" % [root.name, worn]


static func _ask_creatures(node: Node) -> void:
	if node.has_method("refresh_look"):
		@warning_ignore("return_value_discarded")
		node.call("refresh_look")
	for child: Node in node.get_children():
		_ask_creatures(child)
