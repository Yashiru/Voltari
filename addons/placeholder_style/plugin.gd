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
## - **the controls**, which push one value onto every material in the open scene
##   as they move, so a number can be found by looking rather than by guessing
##
## A control is a *trial*. Nothing it does is written anywhere: shut the editor and
## the look is whatever the picker last chose. **Keep** copies the current trial
## into `style_presets.json` under the chosen name, which is what makes it stick
## and what makes the creatures follow — they read the same file.
##
## ## Two lists this file no longer keeps
##
## It used to hold the look names in two hardcoded arrays and the controls in a
## third, and all three drifted. The names come from `style_presets.json` now, the
## controls from `Look.CONTROLS`, and both of those are where the rest of the game
## reads them. A look added to the preset file appears here without this file being
## touched.
##
## The controls are also **rebuilt when the look changes**, because four of them
## belong to one quantiser each. That is the whole of the answer to "why do all the
## looks offer the same settings": after decision 0069 they genuinely do, on one
## shared pipeline, and the four that do not are the four that are hidden.
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

## The bare shared look, with every value at the shader's own default. Not a
## preset, and deliberately so: it is what the defaults look like, which is the
## only way to see them.
const PLAIN: String = "comic"

var _panel: VBoxContainer = null
var _picker: OptionButton = null
var _reach: Label = null
var _controls: VBoxContainer = null
var _naming: LineEdit = null
var _sliders: Dictionary[String, HSlider] = {}
var _labels: Dictionary[String, Label] = {}
var _pickers: Dictionary[String, ColorPickerButton] = {}
var _trial: Dictionary[String, Variant] = {}


func _enter_tree() -> void:
	_panel = VBoxContainer.new()
	_panel.name = "Look"
	# So the dock hands it the whole height it has, which is what the scroll below
	# then has something to distribute.
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_picker = OptionButton.new()
	_picker.tooltip_text = ("The look the game wears, everywhere.\n"
		+ "Written to style.txt, which is what the game reads on load.")
	for name: String in _styles():
		_picker.add_item(name)
	_picker.select(maxi(_index_of(Look.chosen()), 0))
	@warning_ignore("return_value_discarded")
	_picker.item_selected.connect(_choose)
	_panel.add_child(_picker)

	_reach = Label.new()
	_reach.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_panel.add_child(_reach)

	# **The list has to scroll.** There are a few dozen rows and a dock is a
	# column a few hundred pixels tall, so without this everything below the fold
	# is not merely hard to reach, it is unreachable — which is the same defect as
	# a slider that does nothing, arrived at from the other end.
	#
	# The scroll takes the leftover height so the picker stays pinned at the top
	# and **Keep** at the bottom: the two things that are always wanted are the two
	# that must never scroll away.
	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0.0, 220.0)
	_panel.add_child(scroll)

	_controls = VBoxContainer.new()
	# Fills the scroll's width, or every slider is drawn at its minimum size in a
	# column down the left edge.
	_controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_controls)

	var keep: Button = Button.new()
	keep.text = "Keep"
	keep.tooltip_text = ("Merge the controls into style_presets.json under the "
		+ "name above. Until you do, they are a trial and nothing outside this "
		+ "editor session sees them.")
	@warning_ignore("return_value_discarded")
	keep.pressed.connect(_keep)
	_panel.add_child(keep)

	_naming = LineEdit.new()
	_naming.placeholder_text = "new look name"
	_panel.add_child(_naming)

	var fork: Button = Button.new()
	fork.text = "Keep as"
	fork.tooltip_text = ("Write everything the surfaces are currently set to as a "
		+ "new look under that name, on the same quantiser, and wear it.\n"
		+ "Keep merges into an existing look; this one makes another.")
	@warning_ignore("return_value_discarded")
	fork.pressed.connect(_keep_as)
	_panel.add_child(fork)

	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _panel)

	# **Put the scene into the recorded look before showing anything.**
	#
	# Nothing else does. A `MeshLibrary` carries whatever the tile library baked
	# into it when it was built, and a preset edited since then reaches the game at
	# map entry and reaches the editor viewport never — so a Keep looked like it had
	# not been taken: reopen Godot and the old numbers are back on screen and, worse,
	# back on the panel, which reads the surfaces on purpose.
	@warning_ignore("return_value_discarded")
	scene_changed.connect(_scene_opened)
	_dress()
	_rebuild()


func _exit_tree() -> void:
	if _panel == null:
		return
	remove_control_from_docks(_panel)
	_panel.queue_free()
	_panel = null
	_picker = null
	_reach = null
	_controls = null
	_naming = null
	_sliders.clear()
	_labels.clear()
	_pickers.clear()


## Every look on offer: the bare shared look, then every preset in the file.
##
## Read rather than listed. The five that used to be shaders of their own are
## presets like the rest now (decision 0069), so there is no second list to keep in
## step and no separator to explain which half is which.
func _styles() -> PackedStringArray:
	var names: PackedStringArray = PackedStringArray([PLAIN])
	for key: Variant in CreatureView.presets():
		var name: String = str(key)
		# `_comment` and the `_note` beside each preset are prose for whoever opens
		# the file. Anything underscored is not a look.
		if not name.begins_with("_"):
			@warning_ignore("return_value_discarded")
			names.append(name)
	return names


## Which item of the picker carries a name. `get_item_text` rather than an index
## sum, so reordering the preset file cannot silently shift the selection.
func _index_of(style: String) -> int:
	for index: int in range(_picker.item_count):
		if _picker.get_item_text(index) == style:
			return index
	return -1


## The name the picker is showing.
func _picked() -> String:
	if _picker.selected < 0:
		return PLAIN
	return _picker.get_item_text(_picker.selected)


## The quantiser the chosen look resolves to — `comic`, `bands`, `step`, `smooth`
## or `ramp`. Which four of the controls are offered depends on it.
func _quantiser() -> String:
	var mode: int = CreatureView.mode_of(_picked())
	return CreatureView.MODES[clampi(mode, 0, CreatureView.MODES.size() - 1)]


## Build the controls for the chosen look, and put the reach label back in step.
##
## The whole list is thrown away and remade rather than shown and hidden: the set
## depends on the quantiser, the panel is a few dozen rows, and a rebuild cannot
## leave a stale slider pointing at a uniform the current look does not read.
func _rebuild() -> void:
	_sliders.clear()
	_labels.clear()
	_pickers.clear()
	for child: Node in _controls.get_children():
		_controls.remove_child(child)
		child.queue_free()

	var group: String = ""
	for entry: Dictionary in Look.controls_for(_quantiser()):
		var name: String = str(entry["name"])
		var span: Vector2 = Look.control_range(entry)
		var tint: bool = entry.has("tint")
		# Vocabulary without a control: reset by `Look.wear`, reachable from the
		# preset file, and deliberately not on the panel. Forty rows is a wall.
		if span == Vector2.ZERO and not tint:
			continue
		if str(entry["group"]) != group:
			group = str(entry["group"])
			var heading: Label = Label.new()
			heading.text = group
			_controls.add_child(heading)
		_controls.add_child(_tint(name) if tint else _knob(name, span.x, span.y))

	_show_reach()


## One labelled slider, reading the look's current value for its starting point.
func _knob(name: String, low: float, high: float) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	var label: Label = Label.new()
	row.add_child(label)

	var slider: HSlider = HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = (high - low) / 200.0
	slider.value = _starting(name, low, high)
	slider.tooltip_text = name
	@warning_ignore("return_value_discarded")
	slider.value_changed.connect(_pushed.bind(name))
	row.add_child(slider)

	_sliders[name] = slider
	_labels[name] = label
	label.text = "%s  %.3f" % [name, slider.value]
	return row


## One colour picker. The four tints are values like any other and belong on the
## panel for the same reason the numbers do — `ink_colour` in particular decides
## what every stroke in the look is drawn with.
func _tint(name: String) -> Control:
	var row: VBoxContainer = VBoxContainer.new()
	var label: Label = Label.new()
	label.text = name
	row.add_child(label)

	var button: ColorPickerButton = ColorPickerButton.new()
	button.edit_alpha = false
	button.tooltip_text = name
	var held: Variant = _held(name)
	if typeof(held) == TYPE_COLOR:
		@warning_ignore("unsafe_cast")
		button.color = held as Color
	@warning_ignore("return_value_discarded")
	button.color_changed.connect(_tinted.bind(name))
	row.add_child(button)

	_pickers[name] = button
	return row


## What the surfaces under the open scene actually carry, whatever its type.
func _held(name: String) -> Variant:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	return Look.held_value(root, name)


## Where a slider starts: **what the surfaces actually carry.**
##
## It used to be the preset's value, or the middle of the range when the preset
## said nothing — and a preset is silent about most of the vocabulary. So a slider
## showed 1.25 while the material was on 1.0, and the first nudge jumped the value
## instead of adjusting it, which is what "the control does not really work" looks
## like from the outside.
##
## Falls back to the preset, and then to the middle, only when there is no scene to
## read — which is the one case where no true answer exists.
func _starting(name: String, low: float, high: float) -> float:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root != null:
		var held: float = Look.reading(root, name)
		if not is_nan(held):
			return clampf(held, low, high)
	var values: Dictionary[String, Variant] = CreatureView.preset_values(_picked())
	if values.has(name) and typeof(values[name]) != TYPE_COLOR:
		return clampf(float(values[name]), low, high)
	return (low + high) * 0.5


func _pushed(value: float, name: String) -> void:
	if _labels.has(name):
		_labels[name].text = "%s  %.3f" % [name, value]
	_trial[name] = value
	_push(name, value)


func _tinted(value: Color, name: String) -> void:
	_trial[name] = value
	_push(name, value)


func _push(name: String, value: Variant) -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return
	@warning_ignore("return_value_discarded")
	Look.tune(root, name, value)
	_show_reach()


## Put the open scene into the look that is recorded, and ask any creature in it
## to rebuild.
##
## Called when the dock opens and whenever a scene is opened, because **nothing
## else applies a preset in the editor**. The world does it on load and the tile
## library does it at build time; between those two the viewport shows whatever was
## baked into the `MeshLibrary`, which is why an edited preset used not to survive
## closing Godot.
##
## It does mean opening a map scene marks its library modified. That is honest —
## the library really is carrying different numbers now — and saving it is how the
## bake catches up with the file.
func _dress() -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return
	@warning_ignore("return_value_discarded")
	Look.wear(root, _picked())
	_ask_creatures(root)


func _scene_opened(_root: Node) -> void:
	if _panel == null:
		return
	_trial.clear()
	_dress()
	_rebuild()


func _choose(_index: int) -> void:
	var wanted: String = _picked()
	var wrote: Error = Look.choose(wanted)
	if wrote != OK:
		push_warning("cannot record the look: %s" % error_string(wrote))
		return

	_trial.clear()
	var root: Node = EditorInterface.get_edited_scene_root()
	if root != null:
		@warning_ignore("return_value_discarded")
		Look.wear(root, wanted)
		# A creature holds its own materials and rebuilds them rather than being
		# written to, so it is asked rather than dressed.
		_ask_creatures(root)
	# After the change, not before: the controls are meant to show what the
	# surfaces now carry, and before the change that is the previous look's values.
	_rebuild()


## Writes the trial into the preset file, under the chosen name.
##
## Merged rather than replaced: a preset carries values no control offers, and a
## Keep that dropped them would quietly rewrite a look instead of adjusting it.
##
## **Every look can be kept now.** `toon` and its four siblings were shaders rather
## than presets, so this refused them — which meant the one look you could not save
## was the one you had just spent an hour tuning.
func _keep() -> void:
	if _trial.is_empty():
		push_warning("nothing to keep — no control has been moved")
		return
	var wanted: String = _picked()
	var presets: Dictionary = CreatureView.presets()
	if not presets.has(wanted):
		push_warning(("%s is the shared look at its own defaults, which is not a "
			+ "preset. Pick one of the named looks to write into.") % wanted)
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
		fields[name] = _written(_trial[name])

	if not _write(presets):
		return
	_trial.clear()
	print("look: kept %s" % wanted)


## Writes what the surfaces are currently set to as a **new** look, and wears it.
##
## Where **Keep** merges a trial into a look that exists, this makes another one —
## on the same quantiser, because a new set of numbers is a new look and a new way
## of stepping the light would be a new branch of the shader.
##
## It writes everything that differs from the shader's own defaults rather than
## only what was moved this session. A new preset has to stand on its own: `wear`
## resets the vocabulary before applying one, so a fork that carried only the trial
## would come back wearing `comic`'s defaults for everything else.
func _keep_as() -> void:
	var wanted: String = _naming.text.strip_edges()
	if wanted.is_empty():
		push_warning("name the new look first")
		return
	if wanted.begins_with("_"):
		push_warning("a leading underscore marks prose in that file, not a look")
		return
	var presets: Dictionary = CreatureView.presets()
	if presets.has(wanted) or wanted == PLAIN:
		push_warning("%s already exists — use Keep to write into it" % wanted)
		return
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null or Look.worn_under(root).is_empty():
		push_warning("nothing in this scene wears the look, so there is nothing to "
			+ "read a new one off")
		return

	var fields: Dictionary = {}
	var settings: Dictionary[String, Variant] = Look.settings_under(root)
	for name: String in settings:
		fields[name] = _written(settings[name])
	presets[wanted] = {
		"shader": _quantiser(),
		"_note": "Kept from the panel.",
		"uniforms": fields,
	}
	if not _write(presets):
		return

	# Offered and worn immediately: a look you have just named and cannot then
	# select is the same dead end as one you could not save.
	_picker.clear()
	for name: String in _styles():
		_picker.add_item(name)
	_picker.select(maxi(_index_of(wanted), 0))
	_naming.text = ""
	_trial.clear()
	@warning_ignore("return_value_discarded")
	Look.choose(wanted)
	_rebuild()
	print("look: kept %s as a new look, %d value(s)" % [wanted, fields.size()])


## A value as the preset file spells it: a colour as `#rrggbb`, anything else as
## itself, so a kept look reads like the ones written by hand.
static func _written(value: Variant) -> Variant:
	if typeof(value) == TYPE_COLOR:
		@warning_ignore("unsafe_cast")
		return "#" + (value as Color).to_html(false)
	return value


## The preset file, or a warning saying why not.
func _write(presets: Dictionary) -> bool:
	var path: String = CreatureView.SHARED + CreatureView.PRESET_FILE
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("cannot write %s: %s"
			% [path, error_string(FileAccess.get_open_error())])
		return false
	file.store_string(JSON.stringify(presets, "\t"))
	file.close()
	return true


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
	_reach.text = "%s: %d material(s), %s" % [root.name, worn, _quantiser()]


static func _ask_creatures(node: Node) -> void:
	if node.has_method("refresh_look"):
		@warning_ignore("return_value_discarded")
		node.call("refresh_look")
	for child: Node in node.get_children():
		_ask_creatures(child)
