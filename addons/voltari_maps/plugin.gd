@tool
extends EditorPlugin

## The map editor is Godot's, plus what Godot cannot know.
##
## Painting is `GridMap`'s job and this plugin does not reimplement it (spec 14,
## section 3). What it adds is the part that is specific to a Voltari map:
##
## - **Seeing** what a map carries. Warps, zones, events and rest points have no
##   mesh, so the viewport showed nothing at all.
## - **Placing** it. The nodes are addressed by cell and the editor moves things
##   by transform; keeping those two in agreement is what makes a door something
##   you drag rather than something you type.
## - **Checking** it. The validator existed and was reachable only from a test,
##   which is not where anybody is standing when they paint a door.
##
## The cell stays the truth (see `map_placement.gd`). A drag is read, converted,
## and snapped — so nothing is ever left between two cells.


## How far a node has to move before it counts as dragged. Below this it is
## floating-point noise from the transform round trip, and reacting to it would
## mark the scene modified every frame.
const MOVED: float = 0.001

## How often the map under a patch of turf is looked at, in seconds.
##
## **It is also the settling time**, and the two being one number is the point: a
## patch is regrown on the first look that finds the map unchanged, so painting a
## row of fence posts costs one rebuild after the last one rather than one per
## post. Growing a large patch takes a good fraction of a second, and doing it
## under a moving brush would make painting unusable.
##
## A quarter of a second is short enough that the grass has given way before the
## author has finished looking at what they placed.
const SETTLE: float = 0.25

## The overlays, in the order they appear in the menu, and what each is called
## there.
##
## A dictionary rather than two parallel lists: the key is what the gizmo plugin
## switches on and the value is what an author reads, and keeping them in one
## place is what stops a renamed entry checking the wrong box.
const VIEWS: Dictionary[String, String] = {
	VltMapGizmos.MARKERS: "Warps, zones, events, rest points",
	VltMapGizmos.HITBOX: "Hitboxes — what stops you, where it is",
	VltMapGizmos.BLOCKED: "Cells blocked whole",
	VltMapGizmos.EDGE: "Edge of the map",
	VltMapGizmos.PATCH: "Sown patches",
	VltMapGizmos.ARRIVAL: "Player radius, where the player appears",
	VltMapGizmos.STRANDED: "Standable but unreachable",
}

var _gizmos: VltMapGizmos = null
var _dock: VltMapDock = null
var _snap: Button = null
var _views: MenuButton = null
var _place: Button = null
var _tidy: MenuButton = null

## The ghost under the cursor: what is about to be placed, where it would land.
##
## Never given an owner, so it is not saved into the scene and does not appear in
## the scene tree beside the props it is previewing. Freed the moment placing is
## switched off.
var _preview: MeshInstance3D = null

## The tidying gestures, as menu ids.
const TIDY_DROP: int = 0
const TIDY_ALIGN: int = 1
const TIDY_SPREAD: int = 2

## How the next prop is turned and sized. The dock writes to it; the viewport
## reads it (`VltPropBrush`).
var _brush: VltPropBrush = VltPropBrush.new()

## What each map looked like when it was last looked at, and whether it has
## changed since the look before that.
##
## The same two-dictionary shape, and the same reason, as the turf below: the
## first answers "has anything moved", the second "has it stopped moving". The
## overlay is redrawn only when the first says no and the second says yes,
## because rebuilding the shapes walks every mesh on the map and doing that under
## a moving brush would make painting unusable.
var _painted: Dictionary[int, int] = {}
var _unsettled: Dictionary[int, bool] = {}

## Where each node was last put, by instance id. It is what separates "the author
## dragged this" from "this node has never been placed" — and without it, a warp
## authored at cell (7, 3) whose transform is still at the origin would be
## silently rewritten to cell (0, 0) the first time the editor drew it.
var _placed: Dictionary[int, Vector3] = {}

var _sow: Button = null
var _mow: Button = null

## What the map under each patch of turf looked like when it was last looked at,
## by instance id, and whether it has changed since the look before that.
##
## Two dictionaries rather than one, because they answer different questions: the
## first is "has anything moved", the second is "has it stopped moving". A patch is
## regrown only when the first says no and the second says yes.
var _turf: Dictionary[int, int] = {}
var _restless: Dictionary[int, bool] = {}
var _looked: float = 0.0


func _enter_tree() -> void:
	_gizmos = VltMapGizmos.new()
	add_node_3d_gizmo_plugin(_gizmos)

	_dock = VltMapDock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)

	# In the 3D toolbar rather than the dock: it acts on what is selected in the
	# viewport, and a button that acts on a selection belongs beside the
	# selection.
	_snap = Button.new()
	_snap.text = "Snap to cells"
	_snap.tooltip_text = "Move the selected props onto the nearest cell. Height, rotation and scale are left alone."
	_snap.pressed.connect(snap_selection)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _snap)

	# Beside it, and for the same reason: it acts on the cells selected in the
	# GridMap editor.
	_sow = Button.new()
	_sow.text = "Sow foliage"
	_sow.tooltip_text = ("Grow leaves on the cells selected in the GridMap editor.\n"
		+ "Makes one patch node, whose settings are its own — select it to tune them.")
	_sow.pressed.connect(sow_selection)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _sow)

	# The same gesture on the same selection, for the other thing that grows: the
	# short lawn on the ground rather than the leaves on a model. Two buttons and
	# not one with a mode, because an author picking cells knows which of the two
	# they mean and a mode would make them say it twice.
	_mow = Button.new()
	_mow.text = "Sow grass"
	_mow.tooltip_text = ("Grow short grass on the ground of the cells selected in the GridMap editor.\n"
		+ "Makes one patch node, whose settings and colour are its own — select it to tune them.")
	_mow.pressed.connect(sow_grass)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _mow)

	# One menu rather than six buttons. These are questions an author asks one at
	# a time and then stops asking, so they belong behind a list rather than
	# occupying the toolbar for the rest of the session.
	_views = MenuButton.new()
	_views.text = "Voltari view"
	_views.tooltip_text = "What the rules read, drawn over the map."
	_views.switch_on_hover = false
	var popup: PopupMenu = _views.get_popup()
	var index: int = 0
	for key: String in VIEWS:
		popup.add_check_item(VIEWS[key], index)
		popup.set_item_checked(index, _gizmos.shows.get(key, false))
		index += 1
	popup.id_pressed.connect(_on_view_toggled)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _views)

	# Held down rather than a mode you enter and forget: while it is off, the
	# viewport behaves exactly as it did, and painting a `GridMap` is untouched.
	# That matters more than the convenience — this plugin consumes clicks when it
	# is on, and a tool that quietly eats the engine's own gestures is worse than
	# one that needs a button pressed.
	_place = Button.new()
	_place.text = "Place props"
	_place.toggle_mode = true
	_place.tooltip_text = ("Click the ground to place the model picked in the Maps dock.\n"
		+ "A ghost under the cursor shows what will land. Off, the viewport is the engine's own.")
	_place.toggled.connect(_on_placing_toggled)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _place)

	# The three tidying gestures, behind one menu for the reason the views are:
	# they act on a selection, are reached for one at a time, and would otherwise
	# occupy the toolbar for the rest of the session.
	_tidy = MenuButton.new()
	_tidy.text = "Tidy props"
	_tidy.tooltip_text = "Rearrange the selected props."
	_tidy.switch_on_hover = false
	var tidy: PopupMenu = _tidy.get_popup()
	tidy.add_item("Drop to ground", TIDY_DROP)
	tidy.add_item("Align on one line", TIDY_ALIGN)
	tidy.add_item("Space evenly", TIDY_SPREAD)
	tidy.id_pressed.connect(_on_tidy_pressed)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _tidy)

	if _dock != null:
		_dock.brush_changed.connect(_on_brush_changed)
		_on_brush_changed()

	set_process(true)


func _exit_tree() -> void:
	set_process(false)
	if _tidy != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _tidy)
		_tidy.queue_free()
		_tidy = null
	if _place != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _place)
		_place.queue_free()
		_place = null
	if _views != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _views)
		_views.queue_free()
		_views = null
	if _mow != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _mow)
		_mow.queue_free()
		_mow = null
	if _sow != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _sow)
		_sow.queue_free()
		_sow = null
	if _gizmos != null:
		remove_node_3d_gizmo_plugin(_gizmos)
		_gizmos = null
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
	if _snap != null:
		remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _snap)
		_snap.queue_free()
		_snap = null
	_drop_preview()
	_placed.clear()
	_turf.clear()
	_restless.clear()
	_painted.clear()
	_unsettled.clear()


func _process(delta: float) -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return

	# The whole edited scene, not only the selection. A node nobody has clicked
	# still has to be drawn where it says it is, or half the map would appear at
	# the origin until somebody selected it.
	for node: Node3D in _placed_nodes(root):
		_agree(node)

	_looked += delta
	if _looked < SETTLE:
		return
	_looked = 0.0

	# The model list follows whichever map is open. Cheap: the dock returns at
	# once unless the library has actually changed.
	if _dock != null:
		_dock.show_palette(_palette_of(_brush_map()))
	for patch: TurfPatch in _turf_patches(root):
		_follow(patch)
	if _watching():
		for map: VltWorldMap in _maps(root):
			_follow_map(map)


## Whether any overlay drawn from what is painted is switched on.
##
## Nothing is looked at when they are all off, so an author who never opens the
## menu pays nothing at all for it. The markers are not in this list: they are
## drawn from nodes, and a node that moves already redraws its own gizmo.
func _watching() -> bool:
	for key: String in [
		VltMapGizmos.HITBOX, VltMapGizmos.BLOCKED,
		VltMapGizmos.EDGE, VltMapGizmos.PATCH, VltMapGizmos.ARRIVAL,
		VltMapGizmos.STRANDED,
	]:
		if _gizmos.shows.get(key, false):
			return true
	return false


## Redraws one map's overlay if what is painted has changed and then settled.
##
## **Not on the change itself**, for the reason the turf below has: a brush
## dragged across ten cells is ten changes, and rebuilding the shapes on each of
## them walks every mesh on the map ten times. Waiting for one look that finds
## nothing new turns a whole stroke into one rebuild.
func _follow_map(map: VltWorldMap) -> void:
	var id: int = map.get_instance_id()
	var now: int = VltMapOverlay.signature_of(map)

	if not _painted.has(id):
		# First sight. What is painted is what the overlay was drawn from, so
		# there is nothing to do but remember it.
		_painted[id] = now
		return

	if _painted[id] != now:
		_painted[id] = now
		_unsettled[id] = true
		return

	if _unsettled.has(id) and _unsettled[id]:
		_unsettled[id] = false
		# The shapes are a cache on the map, and what they were built from has
		# just changed. Forgetting them is what stops the overlay drawing the
		# wall that was there a moment ago.
		map.forget_shapes()
		map.update_gizmos()


## Switches one overlay, and redraws what it is drawn on.
func _on_view_toggled(id: int) -> void:
	var keys: Array = VIEWS.keys()
	if id < 0 or id >= keys.size():
		return

	var key: String = keys[id]
	var now: bool = not _gizmos.shows.get(key, false)
	_gizmos.shows[key] = now
	_views.get_popup().set_item_checked(id, now)
	refresh_overlay()


## Redraws every gizmo in the edited scene.
##
## The whole scene, because a switch is not about a selection: turning hitboxes
## on has to show every hitbox, not the one belonging to whatever happens to be
## clicked.
func refresh_overlay() -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return
	for map: VltWorldMap in _maps(root):
		map.forget_shapes()
		map.update_gizmos()
	for node: Node3D in _placed_nodes(root):
		node.update_gizmos()


func _maps(root: Node) -> Array[VltWorldMap]:
	var found: Array[VltWorldMap] = []
	var here: VltWorldMap = root as VltWorldMap
	if here != null:
		found.append(here)
	for child: Node in root.get_children():
		found.append_array(_maps(child))
	return found


## Regrows one patch of turf if the map under it has changed and then settled.
##
## **Not on the change itself.** A brush dragged across ten cells is ten changes,
## and a patch that regrew on each of them would drag the editor to a halt. Waiting
## for one look that finds nothing new turns a whole stroke into one rebuild.
func _follow(patch: TurfPatch) -> void:
	if not patch.follow_map:
		return
	var id: int = patch.get_instance_id()
	var now: int = patch.map_signature()

	if not _turf.has(id):
		# First sight. What the map looks like now is what it is supposed to look
		# like — the patch was grown from it — so there is nothing to do but
		# remember it.
		_turf[id] = now
		return

	if _turf[id] != now:
		_turf[id] = now
		_restless[id] = true
		return

	if _restless.has(id) and _restless[id]:
		_restless[id] = false
		patch.resow()


func _turf_patches(root: Node) -> Array[TurfPatch]:
	var found: Array[TurfPatch] = []
	var here: TurfPatch = root as TurfPatch
	if here != null:
		found.append(here)
	for child: Node in root.get_children():
		found.append_array(_turf_patches(child))
	return found


func _placed_nodes(root: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child: Node in root.get_children():
		if VltMapPlacement.is_placed(child):
			found.append(child as Node3D)
		found.append_array(_placed_nodes(child))
	return found


## Brings a node's cell and its transform into agreement, whichever of them moved.
func _agree(node: Node3D) -> void:
	var map: VltWorldMap = VltMapPlacement.map_of(node)
	var anchor: Vector2i = VltMapPlacement.anchor_of(node)
	if anchor == VltMapPlacement.INVALID:
		return

	var id: int = node.get_instance_id()
	var wanted: Vector3 = VltMapPlacement.centre_of(map, anchor)

	if not _placed.has(id):
		# First sight. The cell is the truth, so the transform is the one that
		# moves — including for every node authored before this plugin existed.
		_put(node, id, wanted)
		return

	if node.position.distance_to(_placed[id]) > MOVED:
		# Dragged in the viewport. Read where it landed, then snap.
		var landed: Vector2i = VltMapPlacement.cell_at(map, node.position)
		VltMapPlacement.set_anchor(node, landed)
		_put(node, id, VltMapPlacement.centre_of(map, landed))
		return

	if node.position.distance_to(wanted) > MOVED:
		# Typed in the inspector. The transform follows.
		_put(node, id, wanted)


## Moves the selected props onto the nearest cell.
##
## Props are ordinary nodes, not grid cells: **a `GridMap` cell carries an item
## and one of 24 orientations, and no scale at all.** Anything whose size you want
## to choose has to be a node in the scene, placed and scaled like any other — so
## the grid cannot snap it and something has to offer to.
##
## On demand rather than continuously. A prop half a cell into a doorway is a
## legitimate thing to want, and a snap that could not be declined would make
## free placement impossible rather than optional.
##
## Rotation, scale and height are never touched.
func snap_selection() -> void:
	var selected: Array[Node] = EditorInterface.get_selection().get_selected_nodes()
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Snap to cells")

	var moved: int = 0
	for node: Node in selected:
		var spatial: Node3D = node as Node3D
		if spatial == null:
			continue
		# The placed nodes already live on a cell and are snapped every frame;
		# putting them through this too would be a second answer to a question
		# that already has one.
		if VltMapPlacement.is_placed(spatial):
			continue

		var map: VltWorldMap = VltMapPlacement.map_of(spatial)
		if map == null:
			continue

		var wanted: Vector3 = VltMapPlacement.snapped_to_grid(map, spatial.position)
		if wanted.is_equal_approx(spatial.position):
			continue

		undo.add_do_property(spatial, "position", wanted)
		undo.add_undo_property(spatial, "position", spatial.position)
		moved += 1

	undo.commit_action()
	if _dock != null:
		_dock.say_snapped(moved, selected.size())


func _put(node: Node3D, id: int, at: Vector3) -> void:
	node.position = at
	_placed[id] = at
	node.update_gizmos()


## Grows leaves on the cells selected in the GridMap editor.
##
## **This is the only way anything in this game gets foliage.** There is no
## automatic pass and no name to match: a model is bare until somebody selects
## cells and presses this, which is what "where I want, when I want" has to mean
## for it to be true.
##
## One press is one patch, carrying its own settings. Pressing again over other
## cells makes a second patch rather than joining the first, so two areas can be
## sown differently and either can be tuned or deleted without touching the other.
##
## Godot exposes the GridMap editor's own selection (`get_selected_cells`), so
## this reads the selection the author already made with the tool they already
## use, rather than offering a second way to choose cells.
func sow_selection() -> void:
	var grid: GridMap = _selected_grid()
	if grid == null:
		_say("Select a GridMap and some of its cells first.")
		return

	if _grid_editor() == null:
		_say("This Godot does not expose its GridMap editor, so the selection cannot be read.")
		return
	var chosen: Array[Vector3i] = _selected_cells()
	if chosen.is_empty():
		_say("No cells are selected in the GridMap editor. Select some and press again.")
		return

	var patch: VltFoliagePatch = VltFoliagePatch.new()
	patch.name = "Foliage"
	patch.cells = chosen

	var root: Node = EditorInterface.get_edited_scene_root()
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Sow foliage")
	undo.add_do_method(grid.get_parent(), "add_child", patch)
	undo.add_do_method(patch, "set_owner", root)
	undo.add_do_reference(patch)
	undo.add_undo_method(grid.get_parent(), "remove_child", patch)
	undo.commit_action()

	# Set after the node is in the tree: the path is resolved against it, and a
	# patch that regrew before it had a parent would have nothing to read.
	patch.layer = patch.get_path_to(grid)
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(patch)
	print("Sowed %d cell(s): %d leaves. Tune this patch in the inspector."
		% [chosen.size(), patch.leaf_total()])


## Grows short grass on the ground of the cells selected in the GridMap editor.
##
## The twin of `sow_selection`, and deliberately the same gesture: select cells,
## press, get one node carrying its own settings. What differs is only what grows
## — leaves on the surface of a model there, a lawn on the ground here.
func sow_grass() -> void:
	var grid: GridMap = _selected_grid()
	if grid == null:
		_say("Select a GridMap and some of its cells first.")
		return

	if _grid_editor() == null:
		_say("This Godot does not expose its GridMap editor, so the selection cannot be read.")
		return
	var chosen: Array[Vector3i] = _selected_cells()
	if chosen.is_empty():
		_say("No cells are selected in the GridMap editor. Select some and press again.")
		return

	var patch: TurfPatch = TurfPatch.new()
	patch.name = "Turf"

	var scene_root: Node = EditorInterface.get_edited_scene_root()
	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Sow grass")
	undo.add_do_method(grid.get_parent(), "add_child", patch)
	undo.add_do_method(patch, "set_owner", scene_root)
	undo.add_do_reference(patch)
	undo.add_undo_method(grid.get_parent(), "remove_child", patch)
	undo.commit_action()

	# Both set after the node is in the tree: the path is resolved against it, and
	# a patch that grew before it had a parent would have no grid to read.
	patch.layer = patch.get_path_to(grid)
	patch.cells = chosen
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(patch)
	print("Sowed %d cell(s): %d blades. Tune this patch in the inspector."
		% [chosen.size(), patch.blade_total()])


## The cells the GridMap editor has selected, as cells.
static func _selected_cells() -> Array[Vector3i]:
	var chosen: Array[Vector3i] = []
	var editor: GridMapEditorPlugin = _grid_editor()
	if editor == null or not editor.has_selection():
		return chosen
	for cell: Vector3i in editor.get_selected_cells():
		chosen.append(cell)
	return chosen


## The GridMap the author is editing, which is the one they selected.
static func _selected_grid() -> GridMap:
	for node: Node in EditorInterface.get_selection().get_selected_nodes():
		var grid: GridMap = node as GridMap
		if grid != null:
			return grid
	return null


## The engine's own GridMap editor.
##
## Found by searching the editor's own tree, because there is no API that hands a
## plugin to another plugin — `EditorInterface` exposes only `is_plugin_enabled`.
## The class itself is exposed and its selection is readable, which is the part
## that matters; reaching the instance is the part that is not offered.
##
## Returns nothing rather than failing when it cannot be found, so a Godot that
## moved it produces a message an author can act on instead of a crash.
static func _grid_editor() -> GridMapEditorPlugin:
	var base: Control = EditorInterface.get_base_control()
	if base == null or base.get_tree() == null:
		return null
	for node: Node in base.get_tree().root.find_children("", "GridMapEditorPlugin", true, false):
		return node as GridMapEditorPlugin
	return null


## Said through the editor's own warning channel rather than through the dock:
## the dock is somebody else's file today, and a warning is where an author
## already looks when a button does nothing.
func _say(what: String) -> void:
	push_warning(what)


# --- placing props ------------------------------------------------------------


## Which objects this plugin will take viewport clicks for.
##
## The map and its layers, because those are what an author has selected while
## building one — the palette lives on a `GridMap`, so that is what is selected
## most of the time.
##
## Saying yes here does not take the gesture: `_forward_3d_gui_input` passes
## everything straight through unless *Place props* is held down. Without that,
## this plugin would be competing with the engine's own `GridMap` editor for
## every click on a map.
func _handles(object: Object) -> bool:
	return object is VltWorldMap or object is GridMap


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _place == null or not _place.button_pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var moved: InputEventMouseMotion = event as InputEventMouseMotion
	if moved != null:
		# Followed, not consumed: the camera still orbits and pans while the ghost
		# tracks the ground under the cursor.
		_show_preview(camera, moved.position)
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	var click: InputEventMouseButton = event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT or not click.pressed:
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	if not place_at(camera, click.position):
		return EditorPlugin.AFTER_GUI_INPUT_PASS

	# The pending prop is spent, so the ghost has to show the next one rather than
	# the one now standing under it.
	_show_preview(camera, click.position)
	return EditorPlugin.AFTER_GUI_INPUT_STOP


## Puts the ghost where the next prop would land, making one if there is none.
func _show_preview(camera: Camera3D, at: Vector2) -> void:
	var map: VltWorldMap = _brush_map()
	var mesh: Mesh = _brush_mesh(map)
	if map == null or mesh == null:
		_drop_preview()
		return

	var where: Variant = VltMapPlacement.ground_under(map, camera, at)
	if where == null:
		_drop_preview()
		return

	if _preview == null or _preview.get_parent() != map:
		_drop_preview()
		_preview = MeshInstance3D.new()
		# Unshaded and see-through, so it reads as a promise rather than as
		# something already placed. The model's own look is not the point here.
		var ghost: StandardMaterial3D = StandardMaterial3D.new()
		ghost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		ghost.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		ghost.albedo_color = Color(0.4, 0.9, 1.0, 0.45)
		_preview.material_override = ghost
		# No owner: not saved into the scene, and not shown in the scene tree.
		map.add_child(_preview)

	_preview.mesh = mesh
	@warning_ignore("unsafe_cast")
	_preview.transform = _brush.next_at(VltMapPlacement.dropped(map, where as Vector3))


func _drop_preview() -> void:
	if _preview == null:
		return
	if _preview.get_parent() != null:
		_preview.get_parent().remove_child(_preview)
	_preview.queue_free()
	_preview = null


func _on_placing_toggled(on: bool) -> void:
	if not on:
		_drop_preview()


## Puts one prop where a ray through the viewport meets the map's ground.
##
## Returns whether anything was placed, so the caller knows whether the click was
## used. A click that lands on nothing has to fall through, or the viewport stops
## responding as soon as the camera looks at the sky.
func place_at(camera: Camera3D, at: Vector2) -> bool:
	var map: VltWorldMap = _brush_map()
	if map == null:
		return false

	var mesh: Mesh = _brush_mesh(map)
	if mesh == null:
		_say("Pick a prop model in the Maps dock first.")
		return false

	var where: Variant = VltMapPlacement.ground_under(map, camera, at)
	if where == null:
		return false

	@warning_ignore("unsafe_cast")
	var landed: Vector3 = where as Vector3
	_add_prop(map, mesh, _brush.next_at(VltMapPlacement.dropped(map, landed)))
	# Spent: the prop after this one gets its own draw from the spread.
	_brush.placed()
	return true


## The map props are placed on: the first one in the edited scene.
func _brush_map() -> VltWorldMap:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	var maps: Array[VltWorldMap] = _maps(root)
	return null if maps.is_empty() else maps[0]


## The model the brush is set to, out of the map's own palette.
func _brush_mesh(map: VltWorldMap) -> Mesh:
	var library: MeshLibrary = _palette_of(map)
	if library == null or not _brush.ready_to_paint():
		return null
	return library.get_item_mesh(_brush.item)


## The palette a map paints with.
##
## The blocking layer's first, then the terrain's: they are the same library on
## every map the tile builder has produced, and blocking is the one a prop is a
## peer of.
static func _palette_of(map: VltWorldMap) -> MeshLibrary:
	if map == null:
		return null
	if map.blocking != null and map.blocking.mesh_library != null:
		return map.blocking.mesh_library
	if map.terrain != null and map.terrain.mesh_library != null:
		return map.terrain.mesh_library
	return null


## Builds the prop and hands it to the scene, undoably.
##
## Parented to the map rather than to a group node this would have to invent.
## Grouping is an author's decision and the footprint walk reaches any depth, so
## a `Props` node created behind their back would be a structure nobody asked for.
func _add_prop(map: VltWorldMap, mesh: Mesh, at: Transform3D) -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	var library: MeshLibrary = _palette_of(map)
	var named: String = "" if library == null else library.get_item_name(_brush.item)

	var prop: VltProp = VltProp.new()
	# A palette name is a path — `Plants/Bush_1` — and a node name cannot hold a
	# slash. The last part is what an author would call the thing anyway.
	prop.name = named.get_file() if not named.is_empty() else "Prop"

	var part: MeshInstance3D = MeshInstance3D.new()
	part.name = "Model"
	part.mesh = mesh
	prop.add_child(part)
	prop.transform = at

	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action("Place prop")
	undo.add_do_method(map, "add_child", prop)
	# Owners after the node is in the tree, and the child after its parent: a node
	# whose owner is set while it is loose is not saved into the scene.
	undo.add_do_method(prop, "set_owner", root)
	undo.add_do_method(part, "set_owner", root)
	undo.add_do_method(map, "forget_shapes")
	undo.add_do_reference(prop)
	undo.add_undo_method(map, "remove_child", prop)
	undo.add_undo_method(map, "forget_shapes")
	undo.commit_action()

	map.update_gizmos()


# --- tidying what is already placed -------------------------------------------


func _on_tidy_pressed(id: int) -> void:
	match id:
		TIDY_DROP:
			drop_selection()
		TIDY_ALIGN:
			align_selection()
		TIDY_SPREAD:
			spread_selection()


## Sits the selected props on the tile beneath each of them.
##
## Its own gesture rather than something the brush does continuously: a prop
## deliberately sunk into the ground or standing on a ledge is art, and a drop
## that could not be declined would make that impossible rather than optional —
## the same argument *Snap to cells* already makes about the grid.
func drop_selection() -> void:
	_move_selection("Drop to ground", func(map: VltWorldMap, points: Array[Vector3]) -> Array[Vector3]:
		var dropped: Array[Vector3] = []
		for point: Vector3 in points:
			dropped.append(VltMapPlacement.dropped(map, point))
		return dropped
	)


## Moves the selected props onto one line.
func align_selection() -> void:
	_move_selection("Align props", func(_map: VltWorldMap, points: Array[Vector3]) -> Array[Vector3]:
		return VltPropLayout.aligned(points)
	)


## Spaces the selected props evenly between the two outermost of them.
func spread_selection() -> void:
	_move_selection("Spread props", func(_map: VltWorldMap, points: Array[Vector3]) -> Array[Vector3]:
		return VltPropLayout.spread(points)
	)


## The shape all three share: read the selected props' positions, hand them to
## something that rearranges them, write them back undoably.
##
## **The order is the selection's, and the answer is given back in that order.**
## `VltPropLayout` sorts internally where it has to and returns its answer in the
## order it was handed, so a node keeps whichever position was worked out for it.
func _move_selection(
	named: String, rearranged: Callable
) -> void:
	var props: Array[VltProp] = []
	var map: VltWorldMap = null

	for node: Node in EditorInterface.get_selection().get_selected_nodes():
		var prop: VltProp = node as VltProp
		if prop == null:
			continue
		var owned: VltWorldMap = VltMapPlacement.map_of(prop)
		if owned == null:
			continue
		if map == null:
			map = owned
		props.append(prop)

	if props.is_empty():
		_say("Select some props first — %s acts on what is selected." % named.to_lower())
		return

	var was: Array[Vector3] = []
	for prop: VltProp in props:
		was.append(prop.position)

	@warning_ignore("unsafe_cast")
	var wanted: Array[Vector3] = rearranged.call(map, was) as Array[Vector3]
	if wanted.size() != was.size():
		return

	var undo: EditorUndoRedoManager = get_undo_redo()
	undo.create_action(named)
	for index: int in range(props.size()):
		if wanted[index].is_equal_approx(was[index]):
			continue
		undo.add_do_property(props[index], "position", wanted[index])
		undo.add_undo_property(props[index], "position", was[index])
	undo.add_do_method(map, "forget_shapes")
	undo.add_undo_method(map, "forget_shapes")
	undo.commit_action()
	map.update_gizmos()


## The dock's numbers and its picked model, taken as the brush's.
##
## The pending draw is thrown away with them: otherwise the ghost would keep
## showing the old turn and size until something was placed, which is the one
## moment an author is certainly looking at it.
func _on_brush_changed() -> void:
	if _dock == null:
		return
	_brush.item = _dock.picked_item()
	_brush.turn = _dock.turn_value()
	_brush.turn_spread = _dock.turn_spread_value()
	_brush.size = _dock.size_value()
	_brush.size_spread = _dock.size_spread_value()
	_brush.restyled()
