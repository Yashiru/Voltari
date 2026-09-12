@tool
class_name VltMapPlacement
extends RefCounted

## Where a map's nodes are, in the two languages they are said in.
##
## A warp lives on a **cell**, and that is what the game reads. It also has a
## **transform**, and that is what an editor lets you drag. Those have to agree,
## and something has to decide which of them is the truth.
##
## **The cell is the truth.** The transform is placed from it and snapped back
## after any drag. The other direction — leaving the cell to be derived from
## wherever the node happens to sit — would put a rounding step between what an
## author sees and what the game plays, and half-cell placement is exactly the
## mistake that looks fine in the viewport.
##
## It is editor tooling and carries a `class_name` anyway. That is how this
## repository makes a unit testable, and the arithmetic here is worth testing:
## a marker half a cell out is an error small enough to look like art.

## Nothing sits here. A value rather than null, so callers compare rather than
## check.
const INVALID: Vector2i = Vector2i(-2147483648, -2147483648)

## What a `GridMap` uses when nobody has said otherwise. Only reached for a node
## whose map has no terrain layer yet, which is a map somebody is midway through
## building.
const DEFAULT_CELL_SIZE: float = 2.0


static func is_placed(node: Node) -> bool:
	return (
		node is VltWarp
		or node is VltEncounterZone
		or node is VltEvent
		or node is VltRestPoint
	)


## The one cell a node is placed by — a zone's corner, everything else's cell.
static func anchor_of(node: Node3D) -> Vector2i:
	var zone: VltEncounterZone = node as VltEncounterZone
	if zone != null:
		return zone.origin

	var warp: VltWarp = node as VltWarp
	if warp != null:
		return warp.cell

	var event: VltEvent = node as VltEvent
	if event != null:
		return event.cell

	var rest: VltRestPoint = node as VltRestPoint
	if rest != null:
		return rest.cell

	return INVALID


static func set_anchor(node: Node3D, cell: Vector2i) -> void:
	var zone: VltEncounterZone = node as VltEncounterZone
	if zone != null:
		zone.origin = cell
		return

	var warp: VltWarp = node as VltWarp
	if warp != null:
		warp.cell = cell
		return

	var event: VltEvent = node as VltEvent
	if event != null:
		event.cell = cell
		return

	var rest: VltRestPoint = node as VltRestPoint
	if rest != null:
		rest.cell = cell


## Which cells a placed node claims. One for most of them, a rectangle for a
## zone — and the rectangle is what makes this a list rather than a value.
static func cells_of(node: Node3D) -> Array[Vector2i]:
	var zone: VltEncounterZone = node as VltEncounterZone
	if zone != null:
		var covered: Array[Vector2i] = []
		for x: int in range(maxi(0, zone.size.x)):
			for z: int in range(maxi(0, zone.size.y)):
				covered.append(zone.origin + Vector2i(x, z))
		return covered

	var anchor: Vector2i = anchor_of(node)
	return [anchor] if anchor != INVALID else [] as Array[Vector2i]


## The map a placed node belongs to, or null. Walked upward rather than assumed
## to be the direct parent: a map with its doors grouped under a `Warps` node is
## a reasonable thing for somebody to want.
static func map_of(node: Node) -> VltWorldMap:
	var walk: Node = node.get_parent()
	while walk != null:
		var map: VltWorldMap = walk as VltWorldMap
		if map != null:
			return map
		walk = walk.get_parent()
	return null


## How wide a cell is, read from the map's own terrain layer.
##
## Read rather than declared, because the grid already answers it. A constant
## here would be a second place to change, and the first symptom of it being
## wrong is markers that drift further from their cells the further out you look.
##
## `VltWorldMap` answers all three of these questions itself, and this cannot
## ask it. **An editor holds a non-`@tool` script as a placeholder instance and
## refuses to call methods on one**, so a map opened in the editor would throw on
## every gizmo redraw. Reading the `GridMap` directly is a property access, which
## a placeholder does allow. That is the whole reason for the repetition below,
## and it is cheaper than making the engine run in the editor.
static func cell_size(map: VltWorldMap) -> float:
	if map == null or map.terrain == null:
		return DEFAULT_CELL_SIZE
	return map.terrain.cell_size.x


## The centre of a cell, in the map's local space.
##
## Asked of the grid rather than computed, because the grid has an opinion this
## would otherwise have to reproduce: whether cell zero straddles the origin or
## starts at it is a `GridMap` property, and getting it wrong offsets every
## marker by half a cell — an error small enough to look like art.
static func centre_of(map: VltWorldMap, cell: Vector2i) -> Vector3:
	if map == null or map.terrain == null:
		return Vector3(cell.x * DEFAULT_CELL_SIZE, 0.0, cell.y * DEFAULT_CELL_SIZE)
	return map.terrain.map_to_local(Vector3i(cell.x, VltWorldMap.GROUND, cell.y))


## The same point, moved onto the nearest cell.
##
## **The height is left alone.** A prop sunk into the floor or raised onto a ledge
## is art, and a grid has no opinion about it — snapping `y` would undo the one
## adjustment a free-placed object is there to allow.
static func snapped_to_grid(map: VltWorldMap, local: Vector3) -> Vector3:
	var centre: Vector3 = centre_of(map, cell_at(map, local))
	return Vector3(centre.x, local.y, centre.z)


## The top of the terrain tile in a cell, in the map's own space.
##
## **Not the grid plane.** A cell's own height is where the *tile* is drawn, and a
## tile has a thickness: on the maintainer's pack a leafy ground tile's top face
## sits over a metre above its cell. A prop placed at the grid plane therefore
## stands with its feet a metre underground, which reads as the model being wrong
## rather than as the placement being wrong.
##
## Falls back to the plane for a cell with no tile, no palette or no map — there
## is nothing else it could honestly say, and something placed off the edge of the
## terrain has no surface to sit on.
##
## `TurfPatch` works the same height out for its own purposes and cannot share
## this: it is presentation and this is editor tooling, and neither may depend on
## the other. Worth unifying into the engine if a third caller ever wants it.
static func surface_of(map: VltWorldMap, cell: Vector2i) -> float:
	var plane: float = centre_of(map, cell).y
	if map == null or map.terrain == null or map.terrain.mesh_library == null:
		return plane

	var item: int = map.terrain.get_cell_item(Vector3i(cell.x, VltWorldMap.GROUND, cell.y))
	if item == GridMap.INVALID_CELL_ITEM:
		return plane

	var mesh: Mesh = map.terrain.mesh_library.get_item_mesh(item)
	if mesh == null:
		return plane
	return plane + mesh.get_aabb().end.y * maxf(map.terrain.cell_scale, 0.0001)


## The same point, sitting on the tile beneath it.
##
## What "drop to ground" means, and what the brush places at. Both x and z are
## left alone: this answers a height and nothing else.
static func dropped(map: VltWorldMap, local: Vector3) -> Vector3:
	return Vector3(local.x, surface_of(map, cell_at(map, local)), local.z)


## Where a ray through the viewport meets a map's floor, in the map's own space,
## or nothing when it never does.
##
## **A plane, not a collision shape.** The overworld has no physics by design
## (spec 14, section 1), so there is nothing to raycast against — and there should
## not be: a plane at the map's own floor height is exact, needs nothing built,
## and cannot disagree with the grid about where the floor is.
##
## The answer's height is the floor rather than wherever the ray happened to
## cross, which are the same number here and would stop being the same the day a
## caller passes a plane of its own.
##
## `Variant` rather than a flag and an out-parameter, because a `Vector3` is a
## value in GDScript and an out-parameter would be written and thrown away.
## Nothing is the honest answer for a camera looking along the floor or away from
## it, which is most of what happens while turning the view.
static func ground_under(map: VltWorldMap, camera: Camera3D, at: Vector2) -> Variant:
	if map == null or camera == null:
		return null

	var floor_y: float = centre_of(map, Vector2i.ZERO).y
	var placed: Transform3D = map.global_transform
	var hit: Variant = Plane(
		placed.basis.y.normalized(), placed * Vector3(0.0, floor_y, 0.0)
	).intersects_ray(camera.project_ray_origin(at), camera.project_ray_normal(at))

	if hit == null:
		return null

	@warning_ignore("unsafe_cast")
	var local: Vector3 = placed.affine_inverse() * (hit as Vector3)
	return Vector3(local.x, floor_y, local.z)


## Which cell a point in the map's local space falls in.
static func cell_at(map: VltWorldMap, local: Vector3) -> Vector2i:
	if map == null or map.terrain == null:
		return Vector2i(
			int(roundf(local.x / DEFAULT_CELL_SIZE)), int(roundf(local.z / DEFAULT_CELL_SIZE))
		)
	var grid: Vector3i = map.terrain.local_to_map(local)
	return Vector2i(grid.x, grid.z)
