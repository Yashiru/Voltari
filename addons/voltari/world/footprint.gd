@tool
class_name VltFootprint
extends RefCounted

## The shape a model actually occupies on the ground (spec 14, section 2).
##
## **`@tool` so the editor draws the shape the game uses**, not one that merely
## resembles it (decision 0073). Pure static geometry with no state and nothing
## that runs on its own, so being reachable from the editor costs nothing and
## risks nothing.
##
## **A cell is a metre and a model is not.** Blocking whole cells meant a fence
## post owned a square metre and a house owned one square metre out of the twenty
## it covers. Neither is close enough to walk against, and no threshold on which
## cells to take fixes it — the unit is wrong, not the rounding.
##
## So the footprint is a polygon in map-local metres, and what stops you is the
## distance from it. Still pure computation: no physics body, no collision shape,
## nothing the engine resolves. Spec 14 section 1 asked for one thing that stops
## you rather than two, and this is still one thing — it stopped being a lookup
## and did not stop being arithmetic.
##
## ## What is taken, and what is left out
##
## Only the geometry **below two metres**, which is roughly the character: the
## question is what they would walk into. An arch, an eave, a balcony or a canopy
## is walked under and takes no ground. Triangles are clipped to that height
## rather than kept or dropped whole — a wall running from the floor to a roof
## belongs in the footprint and its roof does not, and they are one triangle strip.
##
## ## Why several polygons and not one
##
## One convex hull per **connected piece** of the model. A gazebo is four posts
## and a roof: one hull around all of it would fill the gazebo in and stop anybody
## walking under it, which is the whole point of a gazebo. Four hulls is four
## posts.
##
## Within a piece it is a hull, so a concave piece — an L-shaped house, a bench
## with a gap under the seat — is filled in. That is deliberate: the error is
## always *more* solid than the model, never less, so nothing is ever walked
## through. A notch you want back is a piece the model should have as its own.

## How high off the ground still counts as being in the way, in world metres.
const REACH: float = 2.0

## Points this close together are one point, in model units, when working out
## which triangles belong to the same piece.
##
## Importers split vertices — by material, by normal, by UV seam — so two
## triangles that share an edge on screen routinely share no index at all.
## Welding by position is what makes a piece a piece. Five centimetres is below
## anything an author would model as a gap and above any seam.
const WELD: float = 0.05

## Below this, in square metres, a piece is a sliver of geometry rather than
## something to walk into: a decal, a shadow plane, a stray triangle.
const SLIVER: float = 0.0004

## The outline, in map-local metres. Convex and wound consistently, because
## `Geometry2D.convex_hull` is what produced it.
var outline: PackedVector2Array = PackedVector2Array()


func _init(of: PackedVector2Array = PackedVector2Array()) -> void:
	outline = of


## Whether a disc of `radius` centred on `point` touches this shape.
##
## The disc and not four sample corners. Corners were the rule while a wall was a
## whole cell and nothing was thinner than one; against a five centimetre post,
## four points sixty centimetres apart walk straight through the gap between them.
func blocks(point: Vector2, radius: float) -> bool:
	if outline.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(point, outline):
		return true

	for index: int in range(outline.size()):
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[(index + 1) % outline.size()]
		if Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) < radius:
			return true
	return false


## Which way this shape pushes back at a point: the outward normal of the part of
## it nearest that point.
##
## Worked out from the point rather than from the winding of the outline, so it
## cannot be wrong about which side is outside. A point exactly on an edge falls
## back to the edge's perpendicular, turned away from the middle of the shape.
func normal_at(point: Vector2) -> Vector2:
	if outline.size() < 3:
		return Vector2.ZERO

	var nearest: Vector2 = Vector2.ZERO
	var gap: float = INF
	var edge: Vector2 = Vector2.ZERO

	for index: int in range(outline.size()):
		var a: Vector2 = outline[index]
		var b: Vector2 = outline[(index + 1) % outline.size()]
		var on: Vector2 = Geometry2D.get_closest_point_to_segment(point, a, b)
		var far: float = on.distance_squared_to(point)
		if far < gap:
			gap = far
			nearest = on
			edge = b - a

	var away: Vector2 = point - nearest
	if not away.is_zero_approx():
		return away.normalized()

	var square: Vector2 = Vector2(-edge.y, edge.x).normalized()
	return square if square.dot(nearest - _middle()) > 0.0 else -square


func _middle() -> Vector2:
	var total: Vector2 = Vector2.ZERO
	for point: Vector2 in outline:
		total += point
	return total / float(outline.size())


## Every shape the meshes under a node occupy, in the space of `into`.
##
## The other half of decision 0072's rule. A model placed as a node blocks where
## its mesh is, exactly as a painted one does; what differs is that a node carries
## its own rotation and scale where a cell carries one of twenty-four turns and
## the grid's single scale.
##
## **`below` is a height in `into`'s space, not a distance above the prop.** A
## balcony three metres up takes no ground, and a distance measured from the
## prop's own origin could not say that — it would give every raised thing a
## footprint under it.
##
## **Every mesh under the node contributes its own pieces.** A composed prop is
## several models standing together, and welding across them would fill the gaps
## between them in. That is the gazebo lesson, which cost a revert once.
static func under(root: Node3D, into: Node3D, below: float) -> Array[VltFootprint]:
	var found: Array[VltFootprint] = []
	if root == null or into == null:
		return found

	var shown: Array[MeshInstance3D] = []
	meshes_under(root, shown)

	for part: MeshInstance3D in shown:
		if part.mesh == null:
			continue
		for piece: PackedVector2Array in placed_pieces(part.mesh, _relative_to(into, part), below):
			found.append(VltFootprint.new(piece))

	return found


## Where a node stands relative to an ancestor, by multiplying the local
## transforms between them.
##
## **Not `global_transform`.** That one needs the node to be inside a scene tree,
## and a map built in code — every world fixture, and the thing spec 14 section
## 10 asks the world to be testable as — is not in one. It answers with the local
## transform alone there, silently, so every shape would be measured correctly and
## placed at the origin.
##
## Walking up is the same answer at runtime and in the editor, and the only
## answer anywhere else.
static func _relative_to(root: Node, node: Node3D) -> Transform3D:
	var at: Transform3D = Transform3D.IDENTITY
	var walk: Node3D = node

	while walk != null and walk != root:
		at = walk.transform * at
		walk = walk.get_parent() as Node3D

	return at


## Every `MeshInstance3D` under a node, the node itself included.
##
## **Public because the editor asks it too**, to size a prop to the grid. The turf
## keeps a walk of its own and that is deliberate: it drops a grid and a patch at
## every level, because a patch is not an obstacle to a patch, and nothing about
## the blocking shapes has that exception to make.
##
## **A hidden branch is skipped whole**, itself and everything under it. Hiding a
## node hides what is below it on screen, and a shape nobody can see is not a
## shape anybody should walk into — an author hiding a prop to look behind it
## would otherwise still be stopped by it.
##
## The local flag rather than `is_visible_in_tree`, because the walk is top-down
## and a hidden parent never reaches its children.
static func meshes_under(node: Node, into: Array[MeshInstance3D]) -> void:
	var branch: Node3D = node as Node3D
	if branch != null and not branch.visible:
		return

	var part: MeshInstance3D = node as MeshInstance3D
	if part != null:
		into.append(part)

	for child: Node in node.get_children():
		meshes_under(child, into)


## Every shape a blocking layer holds.
##
## Each item's own outlines are worked out once however many cells hold it: a map
## is a thousand cells and a dozen models.
static func on(grid: GridMap, below: float = REACH) -> Array[VltFootprint]:
	var found: Array[VltFootprint] = []
	if grid == null or grid.mesh_library == null:
		return found

	var known: Dictionary[int, Array] = {}

	for cell: Vector3i in grid.get_used_cells():
		var item: int = grid.get_cell_item(cell)
		if item == GridMap.INVALID_CELL_ITEM:
			continue

		if not known.has(item):
			var mesh: Mesh = grid.mesh_library.get_item_mesh(item)
			known[item] = [] if mesh == null else pieces_of(mesh, below / maxf(grid.cell_scale, 0.001))

		var at: Transform3D = _placement(grid, cell)
		for piece: Variant in known[item]:
			@warning_ignore("unsafe_cast")
			found.append(VltFootprint.new(_moved(piece as PackedVector2Array, at)))

	return found


## Where the grid draws the model in a cell: its position, its one-of-24
## orientation, and the scale every item is drawn at.
static func _placement(grid: GridMap, cell: Vector3i) -> Transform3D:
	var turn: Basis = grid.get_basis_with_orthogonal_index(grid.get_cell_item_orientation(cell))
	return Transform3D(turn.scaled(Vector3.ONE * grid.cell_scale), grid.map_to_local(cell))


## A flat outline in model units, put where the grid draws it.
static func _moved(piece: PackedVector2Array, at: Transform3D) -> PackedVector2Array:
	var placed: PackedVector2Array = PackedVector2Array()
	for point: Vector2 in piece:
		var there: Vector3 = at * Vector3(point.x, 0.0, point.y)
		placed.append(Vector2(there.x, there.z))
	return placed


## The outline of each connected piece of a model, below a height, in the model's
## own units.
##
## The identity case of `placed_pieces`: a model measured where it was modelled,
## which is what the grid wants because a cell applies its turn and its scale
## afterwards.
static func pieces_of(mesh: Mesh, below: float) -> Array[PackedVector2Array]:
	return placed_pieces(mesh, Transform3D.IDENTITY, below)


## The same, for a model already standing somewhere.
##
## **The triangles are put where they are before anything is measured.** A prop
## carries a rotation and a scale of its own, and a band is a height in the
## world — so slicing in the model's units and transforming afterwards would only
## agree with this when the model happened to be upright and uniformly scaled.
## Doing it in this order needs no such condition and has no second case to keep
## in step with the first.
##
## It also means the weld that decides what is one piece happens in metres rather
## than in whatever a model calls a unit, which is the honest reading: five
## centimetres of gap is five centimetres of gap whatever the thing was modelled
## at.
static func placed_pieces(
	mesh: Mesh, at: Transform3D, below: float
) -> Array[PackedVector2Array]:
	var shapes: Array[PackedVector2Array] = []

	# The triangles with something below the band, and the flat shadow of each.
	#
	# **Filtered before the pieces are worked out, not after.** What physically
	# joins a gazebo's four posts is its roof, and the roof is above the band: let
	# it into the joining and the four posts come out as one piece, which fills
	# the gazebo in and stops anybody walking under it. Only geometry that is in
	# the way gets a say in what is one thing.
	var low: Array[PackedVector3Array] = []
	var flats: Array[PackedVector2Array] = []
	for triangle: PackedVector3Array in _triangles(mesh, at):
		var flat: PackedVector2Array = _under(triangle, below)
		if flat.is_empty():
			continue
		low.append(triangle)
		flats.append(flat)

	if low.is_empty():
		return shapes

	var joined: PackedInt32Array = _pieces(low)
	var points: Dictionary[int, PackedVector2Array] = {}

	for index: int in range(low.size()):
		var piece: int = _root_of(joined, index)
		if not points.has(piece):
			points[piece] = PackedVector2Array()
		points[piece].append_array(flats[index])

	for piece: int in points:
		var hull: PackedVector2Array = Geometry2D.convex_hull(points[piece])
		if hull.size() >= 3 and absf(_area(hull)) >= SLIVER:
			shapes.append(hull)

	return shapes


# --- reading the mesh ---------------------------------------------------------


## Every triangle of a mesh, put where `at` says it stands.
##
## Transformed here rather than by the caller so that everything downstream —
## the band, the weld, the hull — works in one space and cannot be handed two.
static func _triangles(mesh: Mesh, at: Transform3D) -> Array[PackedVector3Array]:
	var found: Array[PackedVector3Array] = []

	for surface: int in range(mesh.get_surface_count()):
		var arrays: Array = mesh.surface_get_arrays(surface)
		if typeof(arrays[Mesh.ARRAY_VERTEX]) != TYPE_PACKED_VECTOR3_ARRAY:
			continue
		@warning_ignore("unsafe_cast")
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array

		var order: PackedInt32Array = PackedInt32Array()
		if typeof(arrays[Mesh.ARRAY_INDEX]) == TYPE_PACKED_INT32_ARRAY:
			@warning_ignore("unsafe_cast")
			order = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
		else:
			# An unindexed surface is three points a triangle, in order.
			for index: int in range(points.size()):
				order.append(index)

		for index: int in range(0, order.size() - 2, 3):
			found.append(PackedVector3Array([
				at * points[order[index]],
				at * points[order[index + 1]],
				at * points[order[index + 2]],
			]))

	return found


## The flat projection of whatever part of a triangle is below a height.
##
## Clipped, not kept or dropped whole. A wall and the roof it holds up are one
## strip of triangles: dropping any triangle that reaches above the band would
## leave a hole in the wall, and keeping any triangle that starts below it would
## project the whole roof onto the ground.
static func _under(triangle: PackedVector3Array, below: float) -> PackedVector2Array:
	var kept: PackedVector2Array = PackedVector2Array()

	for index: int in range(3):
		var here: Vector3 = triangle[index]
		var next: Vector3 = triangle[(index + 1) % 3]
		var inside: bool = here.y <= below
		var ahead: bool = next.y <= below

		if inside:
			kept.append(Vector2(here.x, here.z))
		if inside == ahead:
			continue

		# One end of this edge is over the line. Where it crosses is a corner of
		# the part that counts.
		var span: float = next.y - here.y
		var along: float = 0.0 if is_zero_approx(span) else (below - here.y) / span
		var cut: Vector3 = here.lerp(next, clampf(along, 0.0, 1.0))
		kept.append(Vector2(cut.x, cut.z))

	return kept


# --- which triangles are one piece --------------------------------------------


## Union-find over the triangles, joined wherever they share a welded corner.
## Returns the parent of each triangle; `_root_of` resolves it.
static func _pieces(triangles: Array[PackedVector3Array]) -> PackedInt32Array:
	var parent: PackedInt32Array = PackedInt32Array()
	parent.resize(triangles.size())
	for index: int in range(triangles.size()):
		parent[index] = index

	var owner_of: Dictionary[Vector3i, int] = {}
	for index: int in range(triangles.size()):
		for corner: Vector3 in triangles[index]:
			var welded: Vector3i = Vector3i(
				roundi(corner.x / WELD), roundi(corner.y / WELD), roundi(corner.z / WELD)
			)
			if owner_of.has(welded):
				_join(parent, index, owner_of[welded])
			else:
				owner_of[welded] = index

	return parent


static func _root_of(parent: PackedInt32Array, index: int) -> int:
	var walk: int = index
	while parent[walk] != walk:
		# Halving as we go: the next lookup of anything on this path is shorter,
		# and a model can be tens of thousands of triangles.
		parent[walk] = parent[parent[walk]]
		walk = parent[walk]
	return walk


static func _join(parent: PackedInt32Array, one: int, other: int) -> void:
	var first: int = _root_of(parent, one)
	var second: int = _root_of(parent, other)
	if first != second:
		parent[maxi(first, second)] = mini(first, second)


## Twice the signed area of a polygon, halved. Only its size is used, to tell a
## shape from a sliver.
static func _area(polygon: PackedVector2Array) -> float:
	var total: float = 0.0
	for index: int in range(polygon.size()):
		var here: Vector2 = polygon[index]
		var next: Vector2 = polygon[(index + 1) % polygon.size()]
		total += here.x * next.y - next.x * here.y
	return total * 0.5
