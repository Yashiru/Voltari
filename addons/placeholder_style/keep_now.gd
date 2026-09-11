@tool
extends EditorScript

## Keep the open scene's look, without touching the dock.
##
## **The escape hatch.** The panel's buttons live in a dock, and a dock is built
## once when the plugin is enabled — so a fix to the panel needs the plugin
## reloaded, and reloading it re-applies the recorded preset and throws away
## whatever is currently on the materials. If the thing you want to save is exactly
## that trial, the two requirements contradict each other and there is no way out
## through the panel.
##
## This is the way out. An `EditorScript` runs inside the editor, against the open
## scene, right now: no dock, no reload, nothing lost.
##
## ## How to use it
##
## 1. Set `NAME` below to what the look should be called.
## 2. **File → Run** in the script editor, or Ctrl+Shift+X.
## 3. Read the Output panel. It says what it wrote and where.
##
## A name that already exists is **merged into**, the way the panel's Keep does. A
## name that does not is **created**, the way Keep as does, carrying everything the
## surfaces differ from the shader's defaults by — which is what makes a new look
## stand on its own.
##
## It does not change which look the game wears. `style.txt` is the panel's
## business and leaving it alone means running this can only add, never switch.

## What to call it. The only thing to edit.
const NAME: String = "vinyl-mine"


func _run() -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		push_error("no scene open — open the map you have been tuning first")
		return

	var worn: int = Look.worn_under(root).size()
	if worn == 0:
		push_error("nothing under %s wears the look, so there is nothing to read"
			% root.name)
		return

	var wanted: String = NAME.strip_edges()
	if wanted.is_empty() or wanted.begins_with("_"):
		push_error("set NAME at the top of this script to a real name first")
		return

	var settings: Dictionary[String, Variant] = Look.settings_under(root)
	if settings.is_empty():
		push_error("the surfaces are on the shader's own defaults — nothing to keep")
		return

	var presets: Dictionary = CreatureView.presets()
	var quantiser: String = CreatureView.MODES[
		clampi(CreatureView.mode_of(Look.chosen()), 0, CreatureView.MODES.size() - 1)
	]

	var fields: Dictionary = {}
	var made: bool = not presets.has(wanted)
	if not made:
		# Merged, so a look keeps the values this scene says nothing about.
		@warning_ignore("unsafe_cast")
		var entry: Dictionary = presets[wanted] as Dictionary
		var held: Variant = entry.get("uniforms")
		if typeof(held) == TYPE_DICTIONARY:
			@warning_ignore("unsafe_cast")
			fields = held as Dictionary
		var named: Variant = entry.get("shader")
		if typeof(named) == TYPE_STRING:
			quantiser = str(named)

	for name: String in settings:
		var value: Variant = settings[name]
		# Spelled the way the file spells one, so what comes out reads like what was
		# written by hand.
		if typeof(value) == TYPE_COLOR:
			@warning_ignore("unsafe_cast")
			fields[name] = "#" + (value as Color).to_html(false)
		else:
			fields[name] = value

	presets[wanted] = {
		"shader": quantiser,
		"_note": "Kept from the open scene.",
		"uniforms": fields,
	}

	var path: String = CreatureView.SHARED + CreatureView.PRESET_FILE
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s: %s"
			% [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(presets, "\t"))
	file.close()

	print("look: %s %s on quantiser %s, %d value(s), read off %d material(s) in %s"
		% ["created" if made else "merged into", wanted, quantiser, fields.size(),
			worn, root.name])
	print("look: written to %s — pick it in the dock once the plugin is reloaded"
		% path)
