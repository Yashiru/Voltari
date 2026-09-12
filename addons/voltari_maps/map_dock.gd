@tool
class_name VltMapDock
extends VBoxContainer

## The map author's panel: make one, fill the palette, check the lot.
##
## The validator is the button that was missing. It existed and was **only
## reachable from a test** — a door painted to nowhere was caught by remembering
## to run the suite, which is not where anybody is standing when they paint a
## door.
##
## It checks every map at once rather than the one being edited, because the
## mistakes it finds are the ones no single map can see — a warp's destination
## lives in a different file from the warp (spec 14, section 7).
##
## Built in code rather than from a scene. A dock this small is easier to read as
## a list of widgets than as a `.tscn` nobody can diff.
##
## **Everything sits inside a `ScrollContainer`.** A dock does not add one: a bare
## `VBoxContainer` grows to fit its children and reports that height as its
## minimum, so the editor cannot shrink the dock below it and ends up demanding
## more window than the screen has. That is not a cosmetic problem — the panel's
## lower half becomes unreachable, and the whole layout scales as though the
## window were taller than the display.
##
## So the only child of this node is the scroll, and `_body` is what every widget
## is added to. Nothing here may set `SIZE_EXPAND_FILL` on a child of `_body`
## either: inside a scroll there is no leftover height to expand into, and two
## children asking for it is how a list ends up one row tall.

const MAPS: String = "res://game/maps"
const ENCOUNTERS: String = "res://content/generated/encounters"

## Where models are read from, and where the palette built from them is written.
##
## Both default beside the models, because a library built from them belongs with
## them. All of it is committed through LFS (decision 0074), so a clone gets the
## palette as well as the maps — which it did not until that decision, and a
## `GridMap` with no library keeps its cells regardless, staying walkable and
## turning invisible.
const MODELS: String = "res://game/assets/species/brawl_arena"
const LIBRARY: String = "res://game/assets/species/brawl_arena.meshlib"

## Which items get the shader that opens around a walker, by a fragment of their
## name. Typed rather than guessed from the geometry: a rule nobody can see is a
## rule nobody can correct.
const GRASS: String = "grass"

## Which surfaces get each of the three optional layers, comma separated.
##
## **All three empty by default, and that is the point.** They were applied to
## everything once and the maintainer's word for it was that it landed on plenty
## of things they did not want. Applied is now the same as written down.
##
## A fragment names a family — `Wall_Tile` — and a full name names one model. A
## colon narrows it to one material of that model: `Tree:Wood` is the palm trunks
## and not their fronds.
const GRAIN: String = ""
const CONTACT: String = ""
const ROUGH: String = ""

## Where a new game begins. Reachability is the one check that needs a fact no
## map carries, and it is skipped rather than guessed at when this is empty
## (spec 14, section 7).
const ENTRY: String = "starter_field"

var _folder: LineEdit = null
var _entry: LineEdit = null
var _models: LineEdit = null
var _library: LineEdit = null
var _parting: LineEdit = null
var _grain: LineEdit = null
var _contact: LineEdit = null
var _rough: LineEdit = null
var _new_id: LineEdit = null
var _ground: LineEdit = null
var _width: SpinBox = null
var _height: SpinBox = null
var _report: RichTextLabel = null

## What every widget is added to — see the note above. The dock itself holds only
## the scroll.
var _body: VBoxContainer = null

## Emitted when any brush number changes, so whoever holds the brush can take
## them. A signal rather than the dock reaching for the plugin: a panel knows
## what it was typed into and nothing about who cares.
signal brush_changed

var _turn: SpinBox = null
var _turn_spread: SpinBox = null
var _size: SpinBox = null
var _size_spread: SpinBox = null

## The models a prop can be made of, and which one is picked.
##
## **A second picker, not the only one.** Clicking a model in the engine's own
## `GridMap` palette picks it here too, and this list is what answers when no
## layer is selected. The two say the same thing and the most recent click wins.
##
## Reading the engine's palette *alone* was the first attempt and it failed on a
## consequence rather than on the principle: seeing that palette means being in
## paint mode, which takes the same click placing does. That is solved where it
## belongs — placing leaves paint mode — so the palette is a picker again.
var _filter: LineEdit = null
var _palette: ItemList = null

## Which library the list currently shows, so it is refilled when the map changes
## and not on every frame.
var _library_shown: MeshLibrary = null

## The item id behind each row, because the rows are filtered and their indices
## are therefore not ids.
var _rows: Array[int] = []

## The problems the report is currently showing, in the order it shows them.
##
## What a click resolves against. The link carries an index and not a
## destination, because the destination is three values and a URL would be a
## format somebody has to parse back — the report already knows them.
var _shown: Array[VltMapProblem] = []


func _init() -> void:
	name = "Maps"

	var scroll: ScrollContainer = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# Vertically only: the widgets are told to fit the width, so a horizontal bar
	# would only ever appear because something refused to.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	scroll.add_child(_body)

	_folder = _field("Maps folder", MAPS)
	_entry = _field("Entry map", ENTRY)

	var check: Button = Button.new()
	check.text = "Validate maps"
	check.pressed.connect(_on_validate_pressed)
	_body.add_child(check)

	_body.add_child(HSeparator.new())

	_new_id = _field("New map id", "")
	_width = _size_field("Width", 12)
	_height = _size_field("Height", 12)
	_ground = _field("Ground tile (blank: the first)", "")

	var make: Button = Button.new()
	make.text = "New map"
	make.pressed.connect(_on_new_map_pressed)
	_body.add_child(make)

	_body.add_child(HSeparator.new())

	_models = _field("Models folder", MODELS)
	_library = _field("Tile library", LIBRARY)
	_parting = _field("Grass tiles contain (blank: none)", GRASS)
	_grain = _field("Grain on (Item or Item:Material, comma separated)", GRAIN)
	_contact = _field("Ground contact on (Item or Item:Material)", CONTACT)
	_rough = _field("Roughcast on (Item or Item:Material)", ROUGH)

	var build: Button = Button.new()
	build.text = "Build tile library"
	build.pressed.connect(_on_build_pressed)
	_body.add_child(build)

	_body.add_child(HSeparator.new())

	# What a prop is made of. Filtered, because a real palette is hundreds of
	# models and the categories are in their names (`Plants/Bush_1`), so typing
	# "plants" is how anybody finds anything.
	var picked: Label = Label.new()
	picked.text = "Prop model"
	_body.add_child(picked)

	_filter = LineEdit.new()
	_filter.placeholder_text = "Filter, e.g. plants"
	_filter.text_changed.connect(_on_filter_changed)
	_body.add_child(_filter)

	_palette = ItemList.new()
	# A fixed height rather than an expanding one: the scroll owns the leftover
	# space, and a list that expanded would take it all and leave the report at
	# one line.
	_palette.custom_minimum_size = Vector2(0, 150)
	_palette.max_columns = 0
	_palette.item_selected.connect(_on_item_picked)
	_body.add_child(_palette)

	# How a placed prop is turned and sized.
	_turn = _brush_field("Turn (deg)", 0.0, -360.0, 360.0, 1.0)
	_turn_spread = _brush_field("Turn, give or take", 0.0, 0.0, 360.0, 1.0)
	_size = _brush_field("Size", 1.0, 0.01, 100.0, 0.05)
	_size_spread = _brush_field("Size, give or take", 0.0, 0.0, 100.0, 0.05)

	var hint: Label = Label.new()
	hint.text = "Hold “Place props” in the 3D toolbar, then click the ground."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 10)
	_body.add_child(hint)

	_report = RichTextLabel.new()
	_report.bbcode_enabled = true
	_report.fit_content = false
	_report.custom_minimum_size = Vector2(0, 150)
	# A problem with a place is a link, and this is where clicking one arrives.
	_report.meta_clicked.connect(_on_problem_clicked)
	_body.add_child(_report)


## The inputs, reachable so a caller can set them. There is no second way to
## configure a run: the fields are the configuration, and a test drives the same
## ones a person types into.
func folder_field() -> LineEdit:
	return _folder


func entry_field() -> LineEdit:
	return _entry


func models_field() -> LineEdit:
	return _models


func new_id_field() -> LineEdit:
	return _new_id


func ground_field() -> LineEdit:
	return _ground


func size_fields() -> Array[SpinBox]:
	return [_width, _height]


func library_field() -> LineEdit:
	return _library


func parting_field() -> LineEdit:
	return _parting


func rough_field() -> LineEdit:
	return _rough


func grain_field() -> LineEdit:
	return _grain


func contact_field() -> LineEdit:
	return _contact



## Fills the model list from a map's own palette.
##
## Taken from the map being edited rather than from a path typed into this panel:
## the palette a map paints with is the palette its props should come from, and a
## second path here would be a second thing to keep in step.
##
## Cheap to call repeatedly — it returns at once unless the library has actually
## changed, which is what lets the plugin hand it over on its own tick.
func show_palette(library: MeshLibrary) -> void:
	if library == _library_shown:
		return
	_library_shown = library
	_refill()


## Picks a model by id, if the list is showing it.
##
## What lets the engine's own palette drive this list: an author who clicks a
## model in the big palette has picked it, and the panel should agree rather than
## show something else.
func show_picked(id: int) -> void:
	for row: int in range(_rows.size()):
		if _rows[row] != id:
			continue
		if not _palette.is_selected(row):
			_palette.select(row)
			_palette.ensure_current_is_visible()
		return


## Which model a prop will be made of, or -1 when none is picked.
func picked_item() -> int:
	var chosen: PackedInt32Array = _palette.get_selected_items()
	if chosen.is_empty() or chosen[0] >= _rows.size():
		return -1
	return _rows[chosen[0]]


## Rebuilds the rows for the current library and filter, keeping the picked model
## picked if it survived the filter.
func _refill() -> void:
	var was: int = picked_item()
	_palette.clear()
	_rows.clear()

	if _library_shown == null:
		return

	var wanted: String = _filter.text.strip_edges().to_lower()
	for id: int in _library_shown.get_item_list():
		var name_of: String = _library_shown.get_item_name(id)
		# The invisible blocker is a rule, not a model. Offering it as something to
		# place would offer a prop that draws nothing.
		if name_of == VltWorldMap.BLOCKER:
			continue
		if not wanted.is_empty() and not name_of.to_lower().contains(wanted):
			continue

		var row: int = _palette.add_item(name_of, _library_shown.get_item_preview(id))
		_rows.append(id)
		if id == was:
			_palette.select(row)


func _on_filter_changed(_text: String) -> void:
	_refill()
	brush_changed.emit()


func _on_item_picked(_row: int) -> void:
	brush_changed.emit()


## The brush's numbers, reachable so a caller can read them without knowing which
## widget holds which — the same reasoning as the fields above.
func turn_value() -> float:
	return _turn.value


func turn_spread_value() -> float:
	return _turn_spread.value


func size_value() -> float:
	return _size.value


func size_spread_value() -> float:
	return _size_spread.value


## One brush number: a spinner rather than a text field, because every one of
## these is bounded and a typo in a rotation is not worth discovering by placing
## a prop sideways.
func _brush_field(
	label: String, value: float, least: float, most: float, step: float
) -> SpinBox:
	var row: Label = Label.new()
	row.text = label
	_body.add_child(row)

	var spin: SpinBox = SpinBox.new()
	spin.min_value = least
	spin.max_value = most
	spin.step = step
	spin.value = value
	spin.allow_greater = false
	spin.allow_lesser = false
	spin.value_changed.connect(_on_brush_field_changed)
	_body.add_child(spin)
	return spin


func _on_brush_field_changed(_value: float) -> void:
	brush_changed.emit()


func _field(label: String, value: String) -> LineEdit:
	var caption: Label = Label.new()
	caption.text = label
	_body.add_child(caption)

	var edit: LineEdit = LineEdit.new()
	edit.text = value
	_body.add_child(edit)
	return edit


func _size_field(label: String, value: int) -> SpinBox:
	var caption: Label = Label.new()
	caption.text = label
	_body.add_child(caption)

	var spin: SpinBox = SpinBox.new()
	spin.min_value = VltNewMap.SMALLEST
	spin.max_value = 256
	spin.value = value
	_body.add_child(spin)
	return spin


## `pressed` carries no argument and `validate` returns one, which GDScript will
## not connect directly.
func _on_validate_pressed() -> void:
	validate()


## Loads every map in the folder and reports what is wrong with all of them.
##
## Instantiated and freed here. A map is a scene and the validator reads nodes,
## so there is no way to check one without building it — and leaving them in the
## tree would mean the editor holding a second copy of every map.
##
## The problems are returned as well as shown. A button ignores the value; a test
## cannot read a label, and this is the only part of the dock worth asserting.
##
## Returned as sentences and shown as links. The run is the same run — the report
## keeps the problems with their places, and this is the reading of them that a
## test can compare against a string it wrote by hand.
func validate() -> PackedStringArray:
	var maps: Array[VltWorldMap] = []
	var unreadable: PackedStringArray = PackedStringArray()

	for path: String in _scene_paths(_folder.text):
		var packed: PackedScene = load(path) as PackedScene
		var map: VltWorldMap = null
		if packed != null:
			map = packed.instantiate() as VltWorldMap
		if map == null:
			unreadable.append(path)
			continue
		maps.append(map)

	if maps.is_empty():
		# Reported as a problem rather than as a state. Asking to check a folder
		# and being told nothing is wrong with nothing is the answer most likely
		# to be misread.
		var missing: Array[VltMapProblem] = [
			VltMapProblem.of("no maps found in %s" % _folder.text)
		]
		_show(0, missing, unreadable)
		return VltMapValidator.lines(missing)

	var problems: Array[VltMapProblem] = VltMapValidator.problems(
		maps, VltContentPayloads.ids_in(ENCOUNTERS), _entry.text, VltTranslationTable.all_keys()
	)
	var checked: int = maps.size()
	# Safe to free: a problem carries a path and a cell as values, not a
	# reference into the map it came from. Holding one would mean the report
	# keeping every map in the folder alive for as long as it is on screen.
	for map: VltWorldMap in maps:
		map.free()

	_show(checked, problems, unreadable)
	return VltMapValidator.lines(problems)


## Not every scene under the folder is a map — a tile library's source scene
## could reasonably live beside them — so anything that fails to instantiate as
## one is reported rather than counted.
func _scene_paths(folder: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var directory: DirAccess = DirAccess.open(folder)
	if directory == null:
		return found

	for file: String in directory.get_files():
		if file.ends_with(".tscn") or file.ends_with(".scn"):
			found.append("%s/%s" % [folder, file])

	found.sort()
	return found


## Writes the report, with every problem that has a place made clickable.
##
## **The report was a wall of text that told you where to go and would not take
## you there.** A warp at (14, 9) of a map in another file is a sentence anybody
## can read and nobody can act on without opening two scenes and counting cells.
##
## A link per problem, resolved by index into `_shown`: the sentences are written
## by the validator and reading a destination back out of one would mean parsing
## a format that is not a contract.
##
## A problem with nowhere to go is written plainly rather than as a dead link.
## "no map has a rest point" is about the whole world, and a link that did
## nothing would be worse than no link at all.
func _show(
	checked: int, problems: Array[VltMapProblem], unreadable: PackedStringArray
) -> void:
	_shown = problems

	var lines: PackedStringArray = PackedStringArray()

	if problems.is_empty():
		lines.append("[color=lightgreen]%d map(s) checked, nothing wrong.[/color]" % checked)
	else:
		lines.append("[color=orange]%d problem(s) in %d map(s):[/color]" % [
			problems.size(), checked
		])
		for index: int in range(problems.size()):
			var problem: VltMapProblem = problems[index]
			if problem.navigable():
				lines.append("  • [url=%d]%s[/url]" % [index, problem.message])
			else:
				lines.append("  • %s" % problem.message)

	for path: String in unreadable:
		lines.append("[color=gray]not a map, skipped: %s[/color]" % path)

	_say("\n".join(lines))


## Opens the map a problem is on, and selects what the problem is about.
##
## The scene first, then the selection on the next frame: opening one replaces
## the edited scene, and a node picked out of the old tree would be selected in a
## scene that is on its way out.
func _on_problem_clicked(meta: Variant) -> void:
	var index: int = str(meta).to_int()
	if index < 0 or index >= _shown.size():
		return

	var problem: VltMapProblem = _shown[index]
	if not problem.navigable():
		return

	EditorInterface.open_scene_from_path(problem.scene_path)
	if problem.located:
		_reveal.call_deferred(problem.cell)


## Selects whatever is placed on a cell, or the map when nothing is.
##
## A cell is not a thing that can be selected, so the nearest honest answer is
## the node that claims it — the warp, the event, the rest point the problem is
## about. Falling back to the map itself still puts the author in the right
## scene, which is most of the distance.
func _reveal(cell: Vector2i) -> void:
	var map: VltWorldMap = EditorInterface.get_edited_scene_root() as VltWorldMap
	if map == null:
		return

	var target: Node = map
	for child: Node in map.get_children():
		var placed: Node3D = child as Node3D
		if placed == null or not VltMapPlacement.is_placed(placed):
			continue
		if VltMapPlacement.cells_of(placed).has(cell):
			target = placed
			break

	var chosen: EditorSelection = EditorInterface.get_selection()
	chosen.clear()
	chosen.add_node(target)


func _on_new_map_pressed() -> void:
	new_map()


## Writes a map to start from, and opens it.
##
## Opened because a map that was created and not shown is a map somebody has to
## go and find, and the first thing anybody wants to do with a new one is paint
## on it.
func new_map() -> VltNewMap.Result:
	var result: VltNewMap.Result = VltNewMap.create(
		_new_id.text,
		Vector2i(int(_width.value), int(_height.value)),
		_library.text,
		_ground.text,
		_folder.text
	)
	_show_new_map(result)

	if result.worked() and Engine.is_editor_hint():
		EditorInterface.open_scene_from_path(result.path)

	return result


func _show_new_map(result: VltNewMap.Result) -> void:
	if not result.worked():
		_say("[color=orange]%s[/color]" % "\n".join(result.problems))
		return

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[color=lightgreen]%s[/color]" % result.path)
	if not result.ground.is_empty():
		lines.append("  terrain filled with \"%s\"" % result.ground)
	# Said now rather than discovered on the next validation run. A brand new map
	# genuinely cannot recover a defeat, and that is the first thing to fix.
	lines.append(
		"[color=gray]  no warps, zones, events or rest point yet — the validator will say so[/color]"
	)
	_say("\n".join(lines))


func _on_build_pressed() -> void:
	build_library()


## Reads the models folder into the palette a GridMap paints from.
##
## Safe to run again, which is the point: item ids never move, so re-exporting a
## model or adding one to the folder cannot rewrite a map that was painted with
## the old library.
func build_library() -> VltTileLibrary.Report:
	var report: VltTileLibrary.Report = VltTileLibrary.build(
		_models.text, _library.text, _parting.text, _rough.text,
		_grain.text, _contact.text
	)
	_show_build(report)
	return report


func _show_build(report: VltTileLibrary.Report) -> void:
	var lines: PackedStringArray = PackedStringArray()

	if not report.worked():
		lines.append("[color=orange]The library was not written:[/color]")
		for problem: String in report.problems:
			lines.append("  • %s" % problem)
		_say("\n".join(lines))
		return

	lines.append("[color=lightgreen]%d tile(s) in %s[/color]" % [
		report.total(), report.output
	])
	lines.append("  %d new, %d already there" % [report.added.size(), report.kept.size()])

	# The folders the models came from, because a folder under the root **is** a
	# category and the only way to see that the palette will group is a count per
	# folder. Said only when there is more than one: a flat folder has nothing to
	# report and a line saying so is a line in the way.
	if report.categories.size() > 1:
		var counted: PackedStringArray = PackedStringArray()
		for category: String in report.categories:
			counted.append("%s (%d)" % [
				category if not category.is_empty() else "no folder",
				report.categories[category]
			])
		counted.sort()
		lines.append("  %d categories: %s" % [report.categories.size(), ", ".join(counted)])

	if not report.parting.is_empty():
		lines.append("  %d tile(s) open around a walker: %s" % [
			report.parting.size(), ", ".join(report.parting)
		])

	# Said out loud every build, because a fragment that matches nothing looks
	# exactly like a fragment that works until somebody looks at the tile. The
	# number in brackets is how many of that item's surfaces it reached.
	for layer: Array in [["grain", report.grain], ["contact", report.contact],
			["roughcast", report.stucco]]:
		var touched: PackedStringArray = layer[1]
		if not touched.is_empty():
			lines.append("  %s on %d tile(s): %s" % [
				layer[0], touched.size(), ", ".join(touched)
			])

	if not report.orphaned.is_empty():
		# Kept rather than removed, and said out loud so the palette growing a
		# tail is understood rather than discovered.
		lines.append(
			"[color=gray]  %d item(s) no file produces any more, kept so their ids stay taken: %s[/color]"
			% [report.orphaned.size(), ", ".join(report.orphaned)]
		)

	for path: String in report.skipped:
		lines.append("[color=gray]  no mesh in %s[/color]" % path)

	_say("\n".join(lines))


## Reports a snap the 3D toolbar asked for. Here rather than in a popup: the
## answer is a number, and a number that interrupts you is worse than a number
## you can glance at.
func say_snapped(moved: int, selected: int) -> void:
	if selected == 0:
		_say("[color=orange]Nothing selected.[/color]")
		return
	if moved == 0:
		_say("[color=gray]Nothing to move — already on their cells, or not props under a map.[/color]")
		return
	_say("[color=lightgreen]%d of %d moved onto a cell.[/color]" % [moved, selected])


func _say(text: String) -> void:
	_report.clear()
	_report.append_text(text)
	print_rich(text)
