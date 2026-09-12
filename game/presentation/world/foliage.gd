@tool
class_name VltFoliage
extends RefCounted

## Sows small leaves over the surface of a mesh.
##
## What turns a smooth blob into a bush. The source stays where it is and gains a
## surface of leaf-shaped polygons standing on it, each one facing outwards, each
## one **shaded as the blob rather than as itself**.
##
## That last part is the whole idea and it is worth stating on its own: a leaf's
## vertices carry the normal of the surface underneath, not the leaf's own. Give
## each leaf its true normal and a thousand of them catch a thousand different
## tones and the bush reads as a thousand independent flakes. Give them all the
## normal of the ball they grew from and they read as *one ball, covered in
## leaves*. Everything else here is bookkeeping around that sentence.
##
## Reproduced from a public description of Laure De Mey's Unity tool (80.lv, "An
## Awesome Foliage Scattering Tool for Unity"). Behaviour only — no code of it
## exists publicly and none is here.
##
## Three of the five parts of that tool are deliberately absent, because our
## engine does not have the problems they solve:
##
## - **It bakes the lightmap into each card.** Unity's baked lighting cannot reach
##   geometry with no lightmap UVs, so she carries it in the mesh. Our look is
##   `unshaded` and computes its own shading per fragment from the normal
##   (decision 0062), so writing the support's normal gets the same result with
##   nothing baked.
## - **Its shader rotates each card partly towards the camera**, so a card never
##   goes edge-on. Our overworld camera is a fixed world offset and never yaws, so
##   there is nothing to track.
## - **It cross-fades three densities by distance.** That is for an open scene
##   with a free camera. Ours sits at a fixed distance from the player and sees a
##   few metres. Not built until something is measured that asks for it.

## The leaf, in its own plane: a pointed teardrop one unit tall, its stem at the
## origin and its tip at +Y, wound counter-clockwise so the face is the front.
##
## Six points and four triangles. A quad would be two, but a quad needs an alpha
## texture to stop being a rectangle, and this world has no textures at all — so
## the shape is paid for in geometry instead, where it costs no transparency, no
## sorting and no second shader.
const OUTLINE: Array[Vector2] = [
	Vector2(0.0, 0.0),
	Vector2(0.30, 0.28),
	Vector2(0.22, 0.70),
	Vector2(0.0, 1.0),
	Vector2(-0.22, 0.70),
	Vector2(-0.30, 0.28),
]


## What one sowing looks like. Everything an author would reach for, and nothing
## that is a consequence of something else.
class Settings:
	extends RefCounted

	## Leaves per square unit of surface, **in the mesh's own space** — not in
	## game metres. A `GridMap` draws an item at `ART_SCALE`, so the species
	## models are authored about twice the size they appear at, and a density
	## expressed in metres would be wrong by four on every one of them.
	var density: float = 500.0

	## How long a leaf is, stem to tip, **as a share of the model's own height**.
	## Drawn between the two.
	##
	## A share and not a length, because a length is only ever right for one model.
	## Set for a palm eight units tall, an absolute size put leaves a third the
	## height of a three-unit cactus on it — each one sticking far outside the
	## volume it grew on, which reads as a flat sheet of shards planted through the
	## plant rather than as foliage. One share works on both.
	var smallest: float = 0.05
	var largest: float = 0.09

	## How far a leaf may lean off the surface normal, in degrees.
	##
	## Zero lays every leaf flat against the surface, which reads as a printed
	## skin rather than as foliage. Too much turns them edge-on and they thin out,
	## because the face has to keep pointing outwards to survive back-face
	## culling — the tool this is taken from solves that by turning cards towards
	## the camera, which is a thing we do not need and therefore do not have.
	var lean: float = 90.0

	## How far a leaf is pushed out along the normal, as a share of its own size.
	## What lets the silhouette grow ragged instead of staying the blob's.
	var lift: float = 0.0

	## The colour the leaves take, and how much of it they take.
	##
	## At zero a leaf is exactly the colour of the surface it grew on, which is the
	## behaviour this had before the setting existed and the one that needs no
	## thought: the canopy's leaves are canopy-coloured and the bark's are bark.
	## At one they are `colour` and nothing else.
	##
	## In between is where it is actually useful. A leaf a little lighter or a
	## little warmer than the branch reads as a leaf; one that matches it exactly
	## disappears into it, which is most of why a dense sowing comes out as
	## speckle rather than as foliage.
	var colour: Color = Color(0.42, 0.72, 0.34)
	var colour_amount: float = 0.0

	## How much darker a leaf may come out than the branch it grew on, and across
	## how many flat tones.
	##
	## **This is what gives a sown blob volume.** Every leaf taking exactly the
	## colour of its support means a thousand leaves in one flat fill, and the only
	## thing separating them is the terminator — which on this look is a hard step,
	## so most of them read as one mass. A few tones apart and the eye finds the
	## depth on its own.
	##
	## Snapped rather than continuous, and to three by default, for the reason the
	## grain is snapped (decision 0063): a gradient across a flat fill is the polish
	## this look exists to avoid, and patches of flat tone are what a screentone is.
	##
	## Darkening only. Lightening would have to clip somewhere, and a leaf brighter
	## than the lit side of its own branch reads as a hole rather than as a leaf.
	var tone_spread: float = 0.30
	var tone_steps: int = 3

	## How far a leaf's tip swings, as a multiple of what the one wind asks for.
	##
	## **Not a wind of its own.** The direction, the gust and the breath are the
	## world's, shared with the grass and the turf through `wind.gdshaderinc` and
	## global by decision 0061 — a patch with its own direction would be a second
	## wind in the same field. What a patch says is how much *this* foliage answers
	## the one there is: a sheltered bush barely stirs, a crown on a ridge sweeps.
	## At zero it is as still as the model it grew on.
	##
	## Ten rather than one because the wind's scale was set on grass, where a blade
	## is most of a metre; a leaf is a few centimetres and the same fraction is
	## sub-pixel. See `foliage_leaf.gdshader` for what was measured.
	var sway: float = 10.0

	## How much of a leaf is held rather than free, so it pivots at its stem
	## instead of sliding off the branch.
	var stem_hold: float = 0.15

	## Sowings produced per item, each with its own seed.
	##
	## A `GridMap` stamps one item over many cells, so a single sowing would be
	## fifty trees identical leaf for leaf — the repetition decision 0063 just
	## removed from the ground, back at a far more visible scale. Separate items,
	## painted by hand, break it without a runtime that generates per cell.
	var variants: int = 3

	## How large a surface has to be, against the largest one, to be sown at all.
	##
	## **Sowing every surface is wrong and the render says so**: a palm's trunk
	## came out with brown leaves growing off it, which reads as a diseased tree.
	## A model of this kind has one surface that *is* the foliage and others that
	## are the thing holding it up, and the measurement separates them cleanly —
	## the palm's canopy is 125.7 against its trunk's 20.7, the cactus's body is
	## 23.3 against its spines' 1.2.
	##
	## A threshold rather than a rule, because a rule guessed from the geometry is
	## a rule nobody can correct. At zero every surface is sown, which is what an
	## author reaches for when the guess is wrong for their model.
	var dominant_share: float = 0.5


## Only the leaves, with nothing of the source in them.
##
## **This is the one the game uses.** A `GridMap` already draws the bare model at
## its cell, so a sown copy of it would be the same tree drawn twice. The leaves
## are laid over the top as their own mesh instead, which is also what makes them
## removable: delete the patch and the tree is simply bare again.
##
## Empty when there is nothing to sow on — a mesh that is not an `ArrayMesh`
## cannot be read, and an unindexed surface has no triangles to measure.
##
## `seed` makes this deterministic. The same seed gives the same tree, which is
## what lets a map store six numbers and a cell instead of a baked mesh.
static func leaves(source: Mesh, seed: int, settings: Settings) -> ArrayMesh:
	var grown: ArrayMesh = ArrayMesh.new()
	var array_source: ArrayMesh = source as ArrayMesh
	if array_source == null:
		return grown

	var scatter: RandomNumberGenerator = RandomNumberGenerator.new()
	scatter.seed = seed
	var enough: float = _dominant(array_source) * settings.dominant_share
	var span: float = _span_of(array_source)

	for surface: int in range(array_source.get_surface_count()):
		var arrays: Array = array_source.surface_get_arrays(surface)
		if _area_of(arrays) < enough:
			continue
		var sprigs: Array = _leaves_over(arrays, scatter, settings, span)
		if sprigs.is_empty():
			continue
		grown.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, sprigs)
		# The surface's own material, so a leaf is the colour of what it grew
		# from, with nothing anywhere having to know which surface is which —
		# unless a colour was asked for.
		grown.surface_set_material(
			grown.get_surface_count() - 1,
			_coloured(array_source.surface_get_material(surface), settings)
		)

	return grown


## The shader a leaf wears: the shared look, plus the one wind.
const LEAF_SHADER: String = "res://game/presentation/world/foliage_leaf.gdshader"


## The material a leaf wears, from the material of the surface it grew on.
##
## Copied rather than changed: the material belongs to the source mesh, which is
## shared with every other cell drawing the same item, and tinting it in place
## would repaint the tree along with its leaves.
##
## Returns the material untouched when no colour was asked for, and when the
## material is not one of ours — a mesh that never went through the tile library
## has nothing this knows how to read, and guessing would be worse than leaving
## it alone.
static func _coloured(source: Material, settings: Settings) -> Material:
	var dressed: ShaderMaterial = source as ShaderMaterial
	if dressed == null:
		return source

	var branch: Color = Color.WHITE
	var paint: Variant = dressed.get_shader_parameter("albedo")
	if typeof(paint) == TYPE_COLOR:
		@warning_ignore("unsafe_cast")
		branch = paint as Color

	var copy: ShaderMaterial = dressed.duplicate() as ShaderMaterial

	# The same values — the colour, the named preset, the world's overrides — on a
	# shader that also moves. Every one of them exists in both, because both
	# include the shared look; what the leaf shader adds is the wind, whose
	# defaults live in `wind.gdshaderinc` and are therefore the same air the grass
	# and the turf are standing in.
	var moving: Shader = ResourceLoader.load(LEAF_SHADER, "Shader") as Shader
	if moving != null:
		copy.shader = moving

	if settings.colour_amount > 0.0:
		copy.set_shader_parameter(
			"albedo", branch.lerp(settings.colour, clampf(settings.colour_amount, 0.0, 1.0))
		)

	# Always written, so the patch is the one place these are said. The shader's
	# own defaults are the same numbers and exist for a leaf built by something
	# other than a patch — of which there is nothing today.
	copy.set_shader_parameter("leaf_sway", settings.sway)
	copy.set_shader_parameter("stem_hold", settings.stem_hold)
	copy.set_shader_parameter("tone_spread", settings.tone_spread)
	return copy


## The source with its leaves on it, as one mesh.
##
## For looking at one model on its own — a preview, a test. The game does not use
## this: see `leaves`.
static func sown(source: Mesh, seed: int, settings: Settings) -> Mesh:
	var array_source: ArrayMesh = source as ArrayMesh
	if array_source == null:
		return source

	var grown: ArrayMesh = ArrayMesh.new()
	for surface: int in range(array_source.get_surface_count()):
		grown.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, array_source.surface_get_arrays(surface)
		)
		grown.surface_set_material(
			grown.get_surface_count() - 1, array_source.surface_get_material(surface)
		)

	var sprigs: ArrayMesh = leaves(array_source, seed, settings)
	for surface: int in range(sprigs.get_surface_count()):
		grown.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, sprigs.surface_get_arrays(surface)
		)
		grown.surface_set_material(
			grown.get_surface_count() - 1, sprigs.surface_get_material(surface)
		)

	return grown


## How many leaves one sowing of this mesh would add, so a caller can say so
## without building it. Reported rather than discovered in a profiler.
static func leaf_count(source: Mesh, settings: Settings) -> int:
	var array_source: ArrayMesh = source as ArrayMesh
	if array_source == null:
		return 0
	var enough: float = _dominant(array_source) * settings.dominant_share
	var total: int = 0
	for surface: int in range(array_source.get_surface_count()):
		var area: float = _area_of(array_source.surface_get_arrays(surface))
		if area < enough:
			continue
		total += roundi(area * settings.density)
	return total


## What a leaf's size is a share of: the model's own height, or its widest side
## when it is a low, broad thing with barely any height to speak of.
static func _span_of(source: ArrayMesh) -> float:
	var box: AABB = source.get_aabb()
	return maxf(box.size.y, maxf(box.size.x, box.size.z) * 0.5)


## The area of the largest surface, which is what the others are measured against.
static func _dominant(source: ArrayMesh) -> float:
	var largest: float = 0.0
	for surface: int in range(source.get_surface_count()):
		largest = maxf(largest, _area_of(source.surface_get_arrays(surface)))
	return largest


## One surface's worth of leaves, as arrays ready to become a surface.
static func _leaves_over(
	arrays: Array, scatter: RandomNumberGenerator, settings: Settings, span: float
) -> Array:
	if typeof(arrays[Mesh.ARRAY_VERTEX]) != TYPE_PACKED_VECTOR3_ARRAY:
		return []
	if typeof(arrays[Mesh.ARRAY_INDEX]) != TYPE_PACKED_INT32_ARRAY:
		return []
	@warning_ignore("unsafe_cast")
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	@warning_ignore("unsafe_cast")
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	if points.size() < 3 or indices.size() < 3:
		return []

	# The mesh's own normals, when it has them.
	#
	# **Not the cross product of the triangle's edges.** Which way that points
	# depends on the winding convention of whoever authored the mesh, and it is
	# not reliably outwards: on a Godot `SphereMesh` it is inverted, and every
	# leaf grew *into* the ball — measured, the furthest leaf vertex sat at 0.965
	# on a sphere of radius 1. On a model where it is inverted the leaf also
	# carries an inverted normal, so the shading comes out exactly backwards: the
	# shadow lands on the lit side, which is what the maintainer saw on a cactus
	# while the rest of the scene agreed with itself.
	#
	# A mesh's normals are the mesh's own answer to which way is out. This was
	# written once, reverted with an unrelated rework, and is back with a test
	# holding it.
	var carried: PackedVector3Array = PackedVector3Array()
	if typeof(arrays[Mesh.ARRAY_NORMAL]) == TYPE_PACKED_VECTOR3_ARRAY:
		@warning_ignore("unsafe_cast")
		carried = arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array

	# Running total of triangle area, so a triangle is drawn in proportion to how
	# much surface it is. Drawing triangles evenly would crowd every sliver and
	# leave the broad faces bare.
	var reach: PackedFloat32Array = PackedFloat32Array()
	var running: float = 0.0
	var triangle: int = 0
	while triangle + 2 < indices.size():
		var a: Vector3 = points[indices[triangle]]
		var b: Vector3 = points[indices[triangle + 1]]
		var c: Vector3 = points[indices[triangle + 2]]
		running += (b - a).cross(c - a).length() * 0.5
		reach.append(running)
		triangle += 3

	var wanted: int = roundi(running * settings.density)
	if wanted <= 0 or running <= 0.0:
		return []

	var grown: PackedVector3Array = PackedVector3Array()
	var facing: PackedVector3Array = PackedVector3Array()
	var hinge: PackedColorArray = PackedColorArray()
	var stitched: PackedInt32Array = PackedInt32Array()

	for leaf: int in range(wanted):
		var picked: int = _triangle_at(reach, scatter.randf() * running)
		var corner: int = picked * 3
		var a: Vector3 = points[indices[corner]]
		var b: Vector3 = points[indices[corner + 1]]
		var c: Vector3 = points[indices[corner + 2]]

		# Uniform over the triangle. The square root is what stops the points
		# from piling into one corner.
		var edge: float = sqrt(scatter.randf())
		var across: float = scatter.randf()
		var root: Vector3 = a + (b - a) * edge * (1.0 - across) + (c - a) * edge * across

		var out: Vector3 = Vector3.ZERO
		if carried.size() == points.size():
			# Averaged over the triangle rather than interpolated exactly: a leaf
			# is small and its triangle's three corners rarely disagree by
			# anything the eye could find.
			out = (carried[indices[corner]] + carried[indices[corner + 1]]
				+ carried[indices[corner + 2]])
		if out.length_squared() < 1e-12:
			# No normals on the mesh: fall back to the geometry and take the
			# winding for what it is.
			out = (b - a).cross(c - a)
		if out.length_squared() < 1e-12:
			continue
		out = out.normalized()

		_grow(grown, facing, hinge, stitched, root, out, scatter, settings, span)

	if grown.is_empty():
		return []

	var made: Array = []
	made.resize(Mesh.ARRAY_MAX)
	made[Mesh.ARRAY_VERTEX] = grown
	made[Mesh.ARRAY_NORMAL] = facing
	made[Mesh.ARRAY_COLOR] = hinge
	made[Mesh.ARRAY_INDEX] = stitched
	return made


## One leaf, standing at `root` on a surface facing `out`.
static func _grow(
	grown: PackedVector3Array,
	facing: PackedVector3Array,
	hinge: PackedColorArray,
	stitched: PackedInt32Array,
	root: Vector3,
	out: Vector3,
	scatter: RandomNumberGenerator,
	settings: Settings,
	span: float
) -> void:
	# The leaf's own frame: its face points out of the surface, leaned over by a
	# little, and it is spun freely about that face so no two are alike.
	var leaned: Vector3 = _leaned(out, scatter, deg_to_rad(settings.lean))
	var sideways: Vector3 = _across(leaned)
	var upwards: Vector3 = leaned.cross(sideways)
	var spin: float = scatter.randf() * TAU
	var right: Vector3 = sideways * cos(spin) + upwards * sin(spin)
	var up: Vector3 = upwards * cos(spin) - sideways * sin(spin)

	var size: float = lerpf(settings.smallest, settings.largest, scatter.randf()) * span

	# One tone for the whole leaf, drawn once and written to all six of its
	# points — a leaf is a flat shape and shading half of it differently would
	# make it read as two.
	var steps: int = maxi(settings.tone_steps, 1)
	var tone: float = 1.0
	if steps > 1:
		tone = float(scatter.randi() % steps) / float(steps - 1)
	var stem: Vector3 = root + out * (size * settings.lift)
	var first: int = grown.size()

	for point: Vector2 in OUTLINE:
		grown.append(stem + (right * point.x + up * point.y) * size)
		# What the wind needs and the geometry cannot say once it is merged: how
		# far along its own leaf this vertex sits, and how long that leaf is.
		#
		# In the colour channel rather than the UVs, because the UVs are what the
		# shared look samples a texture with — a leaf would then read its branch's
		# artwork at coordinates that mean something else entirely.
		hinge.append(Color(point.y, size, tone, 1.0))
		# **The surface's normal, not the leaf's.** See the class comment: this
		# one line is the difference between a bush and a heap of flakes.
		facing.append(out)

	# **Wound once.** A leaf is a flat shape and has to be visible from either
	# side, which it was given by winding it twice — on the stated grounds that
	# `cull_disabled` "would draw every leaf four times". That is not what
	# `cull_disabled` does: it rasterises each triangle once and accepts either
	# facing. Winding twice submits two triangles and throws one away, which is
	# twice the geometry for an identical image (decision 0078).
	#
	# The shader turns culling off instead. Both readings show the same thing
	# because both faces carried the same normal — the support's — so there was
	# never a seam to hide.
	for corner: int in range(1, OUTLINE.size() - 1):
		stitched.append(first)
		stitched.append(first + corner)
		stitched.append(first + corner + 1)


## `out`, tipped over by up to `most` radians in a random direction.
static func _leaned(out: Vector3, scatter: RandomNumberGenerator, most: float) -> Vector3:
	var sideways: Vector3 = _across(out)
	var upwards: Vector3 = out.cross(sideways)
	var tip: float = scatter.randf() * most
	var way: float = scatter.randf() * TAU
	return (out * cos(tip)
		+ (sideways * cos(way) + upwards * sin(way)) * sin(tip)).normalized()


## Any unit vector at right angles to `along`. Built from whichever axis `along`
## leans on least, because crossing with one it is parallel to gives nothing.
static func _across(along: Vector3) -> Vector3:
	var axis: Vector3 = Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT
	return along.cross(axis).normalized()


## Which triangle a running total lands in.
static func _triangle_at(reach: PackedFloat32Array, at: float) -> int:
	var low: int = 0
	var high: int = reach.size() - 1
	while low < high:
		var middle: int = (low + high) / 2
		if reach[middle] < at:
			low = middle + 1
		else:
			high = middle
	return low


static func _area_of(arrays: Array) -> float:
	if typeof(arrays[Mesh.ARRAY_VERTEX]) != TYPE_PACKED_VECTOR3_ARRAY:
		return 0.0
	if typeof(arrays[Mesh.ARRAY_INDEX]) != TYPE_PACKED_INT32_ARRAY:
		return 0.0
	@warning_ignore("unsafe_cast")
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	@warning_ignore("unsafe_cast")
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var total: float = 0.0
	var triangle: int = 0
	while triangle + 2 < indices.size():
		var a: Vector3 = points[indices[triangle]]
		var b: Vector3 = points[indices[triangle + 1]]
		var c: Vector3 = points[indices[triangle + 2]]
		total += (b - a).cross(c - a).length() * 0.5
		triangle += 3
	return total
