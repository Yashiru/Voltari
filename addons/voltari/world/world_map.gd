@tool
class_name VltWorldMap
extends Node3D

## One map: what exists, what blocks, what leads elsewhere (spec 14, section 3).
##
## Engine-native by decision 0038. The scene is the truth at runtime and nothing
## is exported to a payload — a grid rebuilt from JSON on load would be the same
## information in two places with nothing keeping them equal.
##
## **`@tool` so the editor can ask it what it knows** (decision 0073). The
## overlay draws the shapes that stop you, and the only way to draw the ones the
## game uses is to ask the class the game asks. A non-`@tool` script is held as a
## placeholder in the editor and throws on every method call, so the alternative
## was a second derivation of the footprints beside this one — two answers to the
## question decision 0072 had just given one answer to.
##
## Nothing here runs by itself: no `_ready`, no `_process`, no `_init` that does
## anything. What the editor gets is the same queries a test gets, and
## `forget_shapes` was already written for it.
##
## **Three layers, and only two of them are rules.** `terrain` says which cells
## exist; `blocking` says which of them stop you. Walkability is painted rather
## than inferred from the model standing on the cell, so replacing a rock with a
## bush is a change of art and not a change of rule.
##
## `decor` says nothing at all. Nothing reads it (decision 0054) — it is there so
## that a flower can be painted without claiming a cell exists and without
## stopping anybody.
##
## A cell with no terrain is off the map, and off the map blocks exactly the way
## a wall does. That falls out rather than being special-cased, which is why the
## edge of a map needs no fence painted around it.

## Stable, `snake_case`, never reused for a different map — a save holds it
## (decision 0040), so renaming one is a migration rather than a rename.
@export var map_id: String = ""

## What exists. A cell absent here is off the map.
@export var terrain: GridMap

## What stops you. A cell present here is blocked.
@export var blocking: GridMap

## What is merely there. Read by nobody: this class offers no accessor for it on
## purpose, so that a rule cannot come to depend on decoration by accident.
@export var decor: GridMap

## Cells are (x, z); the overworld is one storey and y is fixed.
const GROUND: int = 0

## The one item in a palette that is not a model: it draws nothing, and a cell
## holding it is blocked whole.
##
## **Two ways to stop somebody, and they are not two answers to one question.** A
## model stops you where its shape is, to the centimetre (`VltFootprint`). This
## stops you everywhere in a cell, which is the answer when nothing stands there
## and the ground itself is the obstacle — a ledge, a hole, a boundary you do not
## want walked over. Neither can express the other, and an author asking for one
## has not been offered the other by mistake.
const BLOCKER: String = "_blocked"

## The shapes on this map, worked out once. Null until asked for.
##
## Built rather than authored, and that is what makes it right rather than
## convenient: a model painted before any of this existed gets its shape the
## first time the map is read, and nothing can ever be stale relative to what is
## painted. There is no baked copy to go out of date, because there is no copy.
var _shapes: Array[VltFootprint] = []
var _shaped: bool = false


## Whether a cell exists and nothing claims the whole of it.
##
## The grid half of the question, asked without the shapes. They are metres and
## belong to `blocked_at`; a walker needs the two separately because the cell it
## stands in and the place it stands are different things.
func is_open(cell: Vector2i) -> bool:
	return _has_cell(terrain, cell) and not _blocks_whole(cell)


## Whether the centre of a cell can be stood on.
##
## Cell granularity, for everything that thinks in cells: reachability, the
## validator, a warp's destination. A shape covering part of a cell leaves it
## walkable, which is the honest answer — you can stand in it, just not
## everywhere in it.
func is_walkable(cell: Vector2i) -> bool:
	if not is_open(cell):
		return false
	var middle: Vector3 = centre_of(cell)
	return not blocked_at(Vector2(middle.x, middle.z), 0.0)


## Whether a disc of `radius` centred on a point touches anything painted.
func blocked_at(point: Vector2, radius: float) -> bool:
	for shape: VltFootprint in footprints():
		if shape.blocks(point, radius):
			return true
	return false


## Which way the shapes at a point push back, as one direction.
##
## Averaged when several answer, so a corner between two walls pushes out of the
## corner rather than out of whichever wall was found first. Zero when nothing
## shaped is there — the edge of the map and a cell blocked whole have no
## surface, and the caller has another answer for those.
func surface_at(point: Vector2, radius: float) -> Vector2:
	var total: Vector2 = Vector2.ZERO
	for shape: VltFootprint in footprints():
		if shape.blocks(point, radius):
			total += shape.normal_at(point)
	return Vector2.ZERO if total.is_zero_approx() else total.normalized()


## Every shape on this map: what is painted, and what is placed.
##
## **The two sources answer to different rules and that is deliberate.** A
## painted model is read as a shape only on a map whose palette says so, because
## the older reading — a painted cell is a blocked cell — is what the maps built
## before shapes still mean, and reading them the new way would open every wall
## narrower than its cell.
##
## A prop has no older reading. It is a node type that did not exist before, so
## placing one is saying what it means, and nothing already painted changes
## because of it (`VltProp`).
func footprints() -> Array[VltFootprint]:
	if not _shaped:
		_shapes.clear()
		if _uses_shapes():
			_shapes = VltFootprint.on(blocking)
		_shapes.append_array(_prop_shapes())
		_shaped = true
	return _shapes


## The shapes the placed props occupy.
##
## The reach is a height in this map's space rather than a distance above each
## prop, so a balcony or a canopy raised out of the way takes no ground — which
## a distance from a prop's own origin could not express.
func _prop_shapes() -> Array[VltFootprint]:
	var found: Array[VltFootprint] = []
	var ceiling: float = centre_of(Vector2i.ZERO).y + VltFootprint.REACH

	for prop: VltProp in props():
		if not prop.blocks:
			continue
		found.append_array(VltFootprint.under(prop, self, ceiling))
	return found


## The props on this map. Grouped or loose, at any depth (`VltProp`).
func props() -> Array[VltProp]:
	return VltProp.props_under(self)


## Whether this map's blocking layer speaks in shapes at all.
##
## **The palette answers it, by holding `_blocked` or not.** A palette carrying
## the invisible item was built by a tool that knows about shapes; one without it
## belongs to a map painted when a cell was the only unit there was, and on that
## map a painted cell means a blocked cell and nothing measures a mesh.
##
## A switch and not a migration, because the two readings genuinely disagree:
## under the old one a wall mesh blocks its whole cell, under the new one it
## blocks where it is. Reading an old map the new way would open every wall
## painted with a model narrower than its cell, quietly, everywhere at once.
func _uses_shapes() -> bool:
	return _blocker_item() != -1


## The id of the invisible item in this map's palette, or -1 for a palette that
## has none — including no palette at all, which is what a clone missing Git LFS
## opens, and what every clone opened before decision 0074.
func _blocker_item() -> int:
	if blocking == null or blocking.mesh_library == null:
		return -1
	return blocking.mesh_library.find_item_by_name(BLOCKER)


## Forgets the shapes, so the next question rebuilds them. For a caller that has
## just changed what is painted — the editor, and a test.
func forget_shapes() -> void:
	_shapes.clear()
	_shaped = false


## Whether the blocking layer claims the whole of a cell, rather than a shape
## inside it.
func _blocks_whole(cell: Vector2i) -> bool:
	if blocking == null or not _has_cell(blocking, cell):
		return false
	if not _uses_shapes():
		# A map from before shapes, or a clone with no palette to measure. Every
		# painted cell is taken at its word — the safe reading, because nothing
		# becomes walkable that was not.
		return true
	return blocking.get_cell_item(Vector3i(cell.x, GROUND, cell.y)) == _blocker_item()


## The warp on a cell, or null. Null rather than a sentinel warp: "there is no
## warp here" is the answer for almost every cell, and inventing an object for
## it would mean every caller checking a field instead of a reference.
func warp_at(cell: Vector2i) -> VltWarp:
	for child: Node in get_children():
		var warp: VltWarp = child as VltWarp
		if warp != null and warp.cell == cell:
			return warp
	return null


func zone_at(cell: Vector2i) -> VltEncounterZone:
	for child: Node in get_children():
		var zone: VltEncounterZone = child as VltEncounterZone
		if zone != null and zone.contains(cell):
			return zone
	return null


## The event a cell triggers, or null. Events fire only at named moments
## (decision 0043), so the moment is part of the question.
func event_at(cell: Vector2i, trigger: VltEvent.Trigger) -> VltEvent:
	for child: Node in get_children():
		var event: VltEvent = child as VltEvent
		if event != null and event.fires_at(cell, trigger):
			return event
	return null


func events() -> Array[VltEvent]:
	var found: Array[VltEvent] = []
	for child: Node in get_children():
		var event: VltEvent = child as VltEvent
		if event != null:
			found.append(event)
	return found


func warps() -> Array[VltWarp]:
	var found: Array[VltWarp] = []
	for child: Node in get_children():
		var warp: VltWarp = child as VltWarp
		if warp != null:
			found.append(warp)
	return found


func zones() -> Array[VltEncounterZone]:
	var found: Array[VltEncounterZone] = []
	for child: Node in get_children():
		var zone: VltEncounterZone = child as VltEncounterZone
		if zone != null:
			found.append(zone)
	return found


## Which cell a point in this map's space falls in.
##
## Asked of the grid rather than computed, because the grid has opinions this
## would otherwise have to reproduce: how wide a cell is, and whether cell zero
## straddles the origin or starts at it. Getting the second wrong offsets
## everything by half a cell, which is small enough to look like art.
func cell_at(local: Vector3) -> Vector2i:
	if terrain == null:
		return Vector2i(int(roundf(local.x)), int(roundf(local.z)))
	var grid: Vector3i = terrain.local_to_map(local)
	return Vector2i(grid.x, grid.z)


## The middle of a cell, in this map's space.
func centre_of(cell: Vector2i) -> Vector3:
	if terrain == null:
		return Vector3(cell.x, 0.0, cell.y)
	return terrain.map_to_local(Vector3i(cell.x, GROUND, cell.y))


## How wide a cell is, in metres.
func cell_width() -> float:
	if terrain == null:
		return 1.0
	return maxf(terrain.cell_size.x, 0.001)


static func _has_cell(layer: GridMap, cell: Vector2i) -> bool:
	if layer == null:
		return false
	return layer.get_cell_item(Vector3i(cell.x, GROUND, cell.y)) != GridMap.INVALID_CELL_ITEM
