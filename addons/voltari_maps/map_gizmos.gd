@tool
class_name VltMapGizmos
extends EditorNode3DGizmoPlugin

## Draws what a map carries, where it carries it.
##
## Warps, zones, events and rest points are bare `Node3D`s: they have no mesh
## because they are not art. In the viewport that makes them invisible, and
## authoring a map meant typing coordinates and running the game to find out
## whether the door was where you meant it.
##
## **The same argument reaches further than those four nodes.** What stops you is
## invisible for the same reason: since decision 0072 an object blocks where its
## mesh is rather than where its cell is, and the difference between a post owning
## its square metre and one owning five centimetres of it cannot be seen at all.
## So the map itself gets a gizmo too, and it draws the rules — the shapes, the
## cells claimed whole, the edge of the terrain, what was sown, and how much room
## the player takes where the player appears. The geometry is `VltMapOverlay`'s;
## this file is the colours, the switches and the drawing.
##
## A gizmo rather than a `@tool` script adding a marker child. The child would be
## real: saved into the scene, present at runtime, and something a later reader
## has to know to ignore. A gizmo exists only while the editor is drawing.
##
## A placed node is drawn in its own local space, which is why the placement
## helper keeps that transform on the cell the node names. A marker that ignored
## the transform would still be right, and would make dragging do nothing. The
## map's overlay is drawn in the map's space, which is the space the rules read
## in — see the note in `VltMapOverlay` about the one thing that makes those two
## the same space.

## Colours, and one job each: where you leave, where things live, where something
## happens, where you come round.
const WARP: String = "warp"
const ZONE: String = "zone"
const EVENT: String = "event"
const REST: String = "rest"

## And the overlays drawn on the map itself rather than on a node: what stops
## you, and where what grows was sown (`VltMapOverlay`).
const HITBOX: String = "hitbox"
const BLOCKED: String = "blocked"
const EDGE: String = "edge"
const PATCH: String = "patch"
const ARRIVAL: String = "arrival"

## The placed nodes, as one switch. They are four colours but one question —
## "where are the things that are not art" — and four checkboxes for it would be
## four ways to ask it.
const MARKERS: String = "markers"

## Which overlays are drawn.
##
## **Only the markers start on**, which is what the viewport did before any of
## the rest existed. The others answer questions an author asks deliberately, and
## a map that opened with every shape, edge and boundary drawn at once would be a
## wireframe nobody could see the art through.
var shows: Dictionary[String, bool] = {
	MARKERS: true,
	HITBOX: false,
	BLOCKED: false,
	EDGE: false,
	PATCH: false,
	ARRIVAL: false,
}

## How far above the node the outline sits.
##
## A cell centre is not at floor level: the grid centres cells vertically by
## default, so a node on a cell sits at mid-height and a ground tile is drawn
## around the same point. The lift has to clear that tile's top half — 0.06 put
## the outline *inside* a 0.2-thick floor, where it z-fights instead of reading.
const LIFT: float = 0.15

## The height of the post standing on a marked cell. A flat outline alone is
## invisible edge-on, which is most of the time when you are looking across a
## map rather than down at it.
const POST: float = 1.4


## Every material is drawn **on top of the geometry**, which is the whole point
## of a diagnostic: a footprint hidden by the model standing on it, or a door
## behind a wall, is exactly the one you needed to look at. The art is what you
## look at the rest of the time, and every one of these has a switch.
func _init() -> void:
	create_material(WARP, Color(0.35, 0.75, 1.0), false, true)
	create_material(ZONE, Color(0.45, 0.9, 0.4), false, true)
	create_material(EVENT, Color(1.0, 0.8, 0.25), false, true)
	create_material(REST, Color(1.0, 0.45, 0.6), false, true)

	# Red for what stops you, and two shades of it: a shape and a cell claimed
	# whole are not two answers to one question, so they are not one colour.
	create_material(HITBOX, Color(1.0, 0.25, 0.2), false, true)
	create_material(BLOCKED, Color(0.85, 0.1, 0.5), false, true)
	# The edge of the world, in the one colour nothing else uses.
	create_material(EDGE, Color(1.0, 1.0, 1.0), false, true)
	# What was sown, in the colour of the thing it grows.
	create_material(PATCH, Color(0.5, 0.95, 0.3), false, true)
	# How much room the player takes, where the player appears.
	create_material(ARRIVAL, Color(0.6, 0.7, 1.0), false, true)


func _get_gizmo_name() -> String:
	return "Voltari map"


## A gizmo for the placed nodes, and one for the map itself.
##
## The map's own gizmo is what draws everything that belongs to no single node —
## the shapes, the painted cells, the boundary. Hanging those off the map rather
## off each grid is what lets them be drawn in one space and switched as one set.
func _has_gizmo(node: Node3D) -> bool:
	return VltMapPlacement.is_placed(node) or node is VltWorldMap


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	var node: Node3D = gizmo.get_node_3d()
	var map: VltWorldMap = node as VltWorldMap
	if map != null:
		_redraw_map(gizmo, map)
		return
	_redraw_placed(gizmo, node)


## What the map carries that no single node owns.
func _redraw_map(gizmo: EditorNode3DGizmo, map: VltWorldMap) -> void:
	_add(gizmo, HITBOX, VltMapOverlay.hitboxes(map))
	_add(gizmo, BLOCKED, VltMapOverlay.blocked(map))
	_add(gizmo, EDGE, VltMapOverlay.edges(map))
	_add(gizmo, PATCH, VltMapOverlay.patches(map))
	# The radius belongs to the walker and is read from it, so the circle drawn
	# here is the body the game actually refuses to fit through gaps.
	_add(gizmo, ARRIVAL, VltMapOverlay.arrivals(map, VltFreeWalker.RADIUS))


## One overlay, if it is switched on and has anything to say.
##
## The emptiness check is not an optimisation: `add_lines` with no lines leaves a
## mesh behind that Godot then has to draw nothing with, once per redraw.
func _add(gizmo: EditorNode3DGizmo, material: String, lines: PackedVector3Array) -> void:
	if not shows.get(material, false) or lines.is_empty():
		return
	gizmo.add_lines(lines, get_material(material, gizmo), false)


func _redraw_placed(gizmo: EditorNode3DGizmo, node: Node3D) -> void:
	if not shows.get(MARKERS, false):
		return

	var map: VltWorldMap = VltMapPlacement.map_of(node)
	var size: float = VltMapPlacement.cell_size(map)
	var anchor: Vector2i = VltMapPlacement.anchor_of(node)
	if anchor == VltMapPlacement.INVALID:
		return

	var lines: PackedVector3Array = PackedVector3Array()

	# Relative to the node, which sits on its anchor cell. A zone spans several,
	# so every cell is drawn at its offset from that corner.
	for cell: Vector2i in VltMapPlacement.cells_of(node):
		var offset: Vector3 = Vector3(
			float(cell.x - anchor.x) * size, 0.0, float(cell.y - anchor.y) * size
		)
		_outline(lines, offset, size)

	var material: String = _material_for(node)
	if material == ZONE:
		# A zone is a region, and a post on every cell of it would be a thicket.
		gizmo.add_lines(lines, get_material(ZONE, gizmo), false)
		return

	_post(lines)
	if node is VltWarp or node is VltRestPoint:
		_arrow(lines, _facing_of(node), size)

	gizmo.add_lines(lines, get_material(material, gizmo), false)


## A square on the floor, centred on the node's cell.
static func _outline(lines: PackedVector3Array, offset: Vector3, size: float) -> void:
	var half: float = size * 0.5
	var corners: Array[Vector3] = [
		offset + Vector3(-half, LIFT, -half),
		offset + Vector3(half, LIFT, -half),
		offset + Vector3(half, LIFT, half),
		offset + Vector3(-half, LIFT, half),
	]

	for index: int in range(corners.size()):
		lines.append(corners[index])
		lines.append(corners[(index + 1) % corners.size()])


static func _post(lines: PackedVector3Array) -> void:
	lines.append(Vector3(0, LIFT, 0))
	lines.append(Vector3(0, POST, 0))


## Which way you end up facing. Drawn because it is the half of a warp nobody
## checks until they arrive walking into a wall.
static func _arrow(lines: PackedVector3Array, facing: VltFacing.Direction, size: float) -> void:
	var delta: Vector2i = VltFacing.DELTAS[facing]
	var direction: Vector3 = Vector3(float(delta.x), 0.0, float(delta.y))
	var tip: Vector3 = direction * size * 0.45 + Vector3(0, POST, 0)
	var side: Vector3 = Vector3(direction.z, 0.0, -direction.x) * size * 0.15

	lines.append(Vector3(0, POST, 0))
	lines.append(tip)
	lines.append(tip)
	lines.append(tip - direction * size * 0.18 + side)
	lines.append(tip)
	lines.append(tip - direction * size * 0.18 - side)


static func _facing_of(node: Node3D) -> VltFacing.Direction:
	var warp: VltWarp = node as VltWarp
	if warp != null:
		return warp.to_facing

	var rest: VltRestPoint = node as VltRestPoint
	if rest != null:
		return rest.facing

	return VltFacing.Direction.SOUTH


static func _material_for(node: Node3D) -> String:
	if node is VltWarp:
		return WARP
	if node is VltEncounterZone:
		return ZONE
	if node is VltRestPoint:
		return REST
	return EVENT
