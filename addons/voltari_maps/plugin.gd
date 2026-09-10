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

	set_process(true)


func _exit_tree() -> void:
	set_process(false)
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
