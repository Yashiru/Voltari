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

var _gizmos: EditorNode3DGizmoPlugin = null
var _dock: VltMapDock = null
var _snap: Button = null

## Where each node was last put, by instance id. It is what separates "the author
## dragged this" from "this node has never been placed" — and without it, a warp
## authored at cell (7, 3) whose transform is still at the origin would be
## silently rewritten to cell (0, 0) the first time the editor drew it.
var _placed: Dictionary[int, Vector3] = {}

var _sow: Button = null
var _mow: Button = null


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

	set_process(true)


func _exit_tree() -> void:
	set_process(false)
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
	_placed.clear()


func _process(_delta: float) -> void:
	var root: Node = EditorInterface.get_edited_scene_root()
	if root == null:
		return

	# The whole edited scene, not only the selection. A node nobody has clicked
	# still has to be drawn where it says it is, or half the map would appear at
	# the origin until somebody selected it.
	for node: Node3D in _placed_nodes(root):
		_agree(node)


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
