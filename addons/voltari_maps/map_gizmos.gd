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
## A gizmo rather than a `@tool` script adding a marker child. The child would be
## real: saved into the scene, present at runtime, and something a later reader
## has to know to ignore. A gizmo exists only while the editor is drawing.
##
## Everything is drawn in the node's own local space, which is why the placement
## helper keeps that transform on the cell the node names. A marker that ignored
## the transform would still be right, and would make dragging do nothing.

## Colours, and one job each: where you leave, where things live, where something
## happens, where you come round.
const WARP: String = "warp"
const ZONE: String = "zone"
const EVENT: String = "event"
const REST: String = "rest"

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


func _init() -> void:
	create_material(WARP, Color(0.35, 0.75, 1.0))
	create_material(ZONE, Color(0.45, 0.9, 0.4))
	create_material(EVENT, Color(1.0, 0.8, 0.25))
	create_material(REST, Color(1.0, 0.45, 0.6))


func _get_gizmo_name() -> String:
	return "Voltari map"


func _has_gizmo(node: Node3D) -> bool:
	return VltMapPlacement.is_placed(node)


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()

	var node: Node3D = gizmo.get_node_3d()
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
