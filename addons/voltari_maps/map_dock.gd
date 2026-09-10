@tool
class_name VltMapDock
extends VBoxContainer

## The map author's panel.
##
## One button so far, and it is the one that was missing: **the validator was
## only reachable from a test**. A door painted to nowhere was caught by running
## the suite, which is not where anybody is standing when they paint a door.
##
## It checks every map at once rather than the one being edited, because the
## mistakes it finds are the ones no single map can see — a warp's destination
## lives in a different file from the warp (spec 14, section 7).
##
## Built in code rather than from a scene. A dock this small is easier to read as
## a list of widgets than as a `.tscn` nobody can diff.

const MAPS: String = "res://game/maps"
const ENCOUNTERS: String = "res://content/generated/encounters"

## Where models are read from, and where the palette built from them is written.
##
## Both default inside the quarantine (decision 0027) because that is where
## third-party models live and a library built from them is derived from them. A
## clone gets the maps and not the palette — a `GridMap` keeps its cells with no
## library at all, so the world stays walkable and turns invisible.
const MODELS: String = "res://game/assets/placeholders/brawl_arena"
const LIBRARY: String = "res://game/assets/placeholders/brawl_arena.meshlib"

## Where a new game begins. Reachability is the one check that needs a fact no
## map carries, and it is skipped rather than guessed at when this is empty
## (spec 14, section 7).
const ENTRY: String = "starter_field"

var _folder: LineEdit = null
var _entry: LineEdit = null
var _models: LineEdit = null
var _library: LineEdit = null
var _report: RichTextLabel = null


func _init() -> void:
	name = "Maps"
	add_theme_constant_override("separation", 6)

	_folder = _field("Maps folder", MAPS)
	_entry = _field("Entry map", ENTRY)

	var check: Button = Button.new()
	check.text = "Validate maps"
	check.pressed.connect(_on_validate_pressed)
	add_child(check)

	add_child(HSeparator.new())

	_models = _field("Models folder", MODELS)
	_library = _field("Tile library", LIBRARY)

	var build: Button = Button.new()
	build.text = "Build tile library"
	build.pressed.connect(_on_build_pressed)
	add_child(build)

	_report = RichTextLabel.new()
	_report.bbcode_enabled = true
	_report.fit_content = false
	_report.custom_minimum_size = Vector2(0, 180)
	_report.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_report)


## The two inputs, reachable so a caller can set them. There is no second way to
## configure a run: the fields are the configuration, and a test drives the same
## ones a person types into.
func folder_field() -> LineEdit:
	return _folder


func entry_field() -> LineEdit:
	return _entry


func models_field() -> LineEdit:
	return _models


func library_field() -> LineEdit:
	return _library


func _field(label: String, value: String) -> LineEdit:
	var caption: Label = Label.new()
	caption.text = label
	add_child(caption)

	var edit: LineEdit = LineEdit.new()
	edit.text = value
	add_child(edit)
	return edit


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
		var missing: PackedStringArray = PackedStringArray(
			["no maps found in %s" % _folder.text]
		)
		_show(0, missing, unreadable)
		return missing

	var problems: PackedStringArray = VltMapValidator.check(
		maps, VltContentPayloads.ids_in(ENCOUNTERS), _entry.text, VltTranslationTable.all_keys()
	)
	var checked: int = maps.size()
	for map: VltWorldMap in maps:
		map.free()

	_show(checked, problems, unreadable)
	return problems


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


func _show(
	checked: int, problems: PackedStringArray, unreadable: PackedStringArray
) -> void:
	var lines: PackedStringArray = PackedStringArray()

	if problems.is_empty():
		lines.append("[color=lightgreen]%d map(s) checked, nothing wrong.[/color]" % checked)
	else:
		lines.append("[color=orange]%d problem(s) in %d map(s):[/color]" % [
			problems.size(), checked
		])
		for problem: String in problems:
			lines.append("  • %s" % problem)

	for path: String in unreadable:
		lines.append("[color=gray]not a map, skipped: %s[/color]" % path)

	_say("\n".join(lines))


func _on_build_pressed() -> void:
	build_library()


## Reads the models folder into the palette a GridMap paints from.
##
## Safe to run again, which is the point: item ids never move, so re-exporting a
## model or adding one to the folder cannot rewrite a map that was painted with
## the old library.
func build_library() -> VltTileLibrary.Report:
	var report: VltTileLibrary.Report = VltTileLibrary.build(_models.text, _library.text)
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


func _say(text: String) -> void:
	_report.clear()
	_report.append_text(text)
	print_rich(text)
