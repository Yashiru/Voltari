# 0072 — A model stops you where it is

## Context

Walkability was a cell: `is_walkable` asked one question of one cell, and a cell
painted in the blocking layer stopped you everywhere in it.

That held while the world was three grey boxes and every obstacle was cell-sized.
It stopped holding the moment a real asset pack arrived. A fence post owns a
square metre it does not fill; a house is five cells across and owns one of them,
so the player walks through the other twenty-four. The maintainer's words were
that objects block with their host cell instead of their mesh, and that the
footprint has to be the real shape of the mesh below two metres, accurate to five
or ten centimetres.

A cell is a metre. The unit was twenty times too coarse, which is not something a
threshold on *which* cells to take can repair — the first attempt did exactly
that and was reverted.

## Options rejected

**A finer occupancy grid, five centimetres.** Rasterise the silhouette into a
mask and keep the lookup. It keeps section 1 in its exact letter and costs about
200 KB on a 64 m map. Rejected in favour of polygons on the maintainer's call:
the precision is capped by construction, and correcting one by hand would need a
fine brush that does not exist.

**Godot's physics.** Static bodies and collision shapes on the models. The least
code and the most exact. Rejected because movement would stop being pure
computation, and with it the determinism at a fixed seed and the ability to test
the world with no engine in the loop — which is what spec 14 section 1 is
protecting, and it is not protecting it out of taste.

**Deriving the whole thing and calling the cell layer obsolete.** Rejected
because a shape cannot express "the ground here is a hole". Both readings are
needed and neither can say what the other says.

**Baking the footprint at placement.** The obvious reading of "compute it when
the object is placed". Rejected once the first attempt showed what baking costs:
objects placed before the feature existed were never reprocessed and kept stale
hitboxes. A derived value cannot go stale because there is no copy of it.

## Decision

The blocking layer says two things, and which one depends on the item.

**`_blocked`** — an invisible item the tile library keeps in every palette — is a
cell blocked whole. A lookup, exactly as before.

**Any model** is the polygon it occupies below two metres, in metres. One convex
hull per connected piece of the mesh, with triangles clipped at the band rather
than kept or dropped whole. Derived when the map is read; never authored, never
stored, so never stale.

Two metres is roughly the character, and the question is what they would walk
into: an arch, an eave, a balcony or a canopy is walked under. Per connected
piece because a gazebo is four posts and a roof, and one hull around all of it
fills the gazebo in. Within a piece it is a hull, so the error is always *more*
solid than the model and never less — nothing is ever walked through.

Touching a shape does not stop you: the component of the move going into the
surface is removed and the rest goes through. Square to it there is nothing left,
which is the only full stop.

A palette without `_blocked` keeps the old reading entirely. The two genuinely
disagree — under the old one a wall mesh blocks its whole cell, under the new one
it blocks where it is — so reading an old map the new way would silently open
every wall painted with a model narrower than its cell.

## Why

The unit was wrong, and the fix has to change the unit. What section 1 actually
protects is that one thing stops you and that it is pure computation; neither is
given up here. What is given up is that the one thing is a *lookup*, which was
never the promise — it was how the promise happened to be kept while everything
was cell-sized.

Deriving rather than authoring is what the first attempt got wrong twice over: a
baked footprint went stale, and a transform stored beside the geometry was read
by the renderer and by nothing else. One truth, computed from the thing itself.

Supersedes the cell-granular reading of section 2 in spec 14. Decisions 0038
(engine-native maps) and 0054 (the third layer is read by nobody) are untouched.
