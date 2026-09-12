# 0075 — A prop is a node, and says so by being one

**Status:** Accepted
**Date:** 2026-09-12
**Refines:** decision 0072 (a model stops you where it is)
**Recorded in:** spec 14, sections 2 and 3

## Context

Everything on a map that was not a marker was painted into a `GridMap`. A cell
carries an item, one of twenty-four orthogonal turns, and no scale of its own —
the layer has one, for all of it.

That is enough to lay a floor and is not enough for anything else. A bench at
fifteen degrees cannot be painted. A boulder wanted half again as large cannot be
painted. A gate made of two posts and a lintel cannot be painted as one thing at
all. The maintainer asked for free rotation and scale before placing, for
composing several models into one placeable object, and for an object to be
selectable from any cell it covers — three requests which are one question, since
none of them can be a cell.

A map already held models placed as ordinary nodes: three `MeshInstance3D` in
`test1`, snapped by a button the editor offers precisely because "a `GridMap`
cell carries an item and one of 24 orientations, and no scale at all". Those
models stopped nobody, and the grass made way for their bounding boxes.

## Decision

**A placed model is a `VltProp`, and it stops you where its geometry is.** The
same answer decision 0072 gave a painted model: the polygon occupied below the
walker's reach, derived when the map is read, never stored. Turning a prop turns
its footprint because the footprint *is* the turned mesh, measured.

**Blocking is a property of the type, not a flag on every mesh.** Making all
geometry on a map block would change what existing maps mean — `test1`'s three
models have never stopped anybody — silently and everywhere at once. That is the
failure 0072 refused when it made the palette, rather than a migration, decide
how a blocking layer is read. A prop has no older reading to be gated by, so it
needs no switch: placing one is the whole of declaring it.

**A prop blocks by default**, with one flag for the exceptions — a flower, a rug,
a sign painted on the ground. The painted layers keep the opposite bargain, where
walkability is authored separately from art. Both are right for their case: a
layer is dragged across a room and wants the rule said once for all of it, and a
prop is placed one at a time and wants the obvious thing to happen.

**The band is a height in the map's space**, not a distance above the prop. Two
metres above the ground rather than two metres above whatever is being measured,
which is the only way a balcony, an eave or a canopy raised out of the way can
take no ground at all.

## Options rejected

**Pre-baked variants in the palette.** Generate items for each rotation and
scale, so everything stays a cell and nothing else changes. Rejected: the values
stay discrete, the palette grows combinatorially, and it answers neither
composition nor selection — two of the three things asked for.

**A transform table beside the grid**, one entry per cell. Rejected as two
sources of truth for one object, which is exactly the staleness 0072 observed and
removed: a baked footprint went out of date, and the fix was to stop keeping a
copy.

**Deriving footprints from every mesh on the map**, no type at all. It is the
smallest change and it is the one that rewrites the meaning of every map already
painted. Rejected for that, not for taste.

## Consequences

**The slicing became one path.** A model measured where it was modelled is the
identity case of a model measured where it stands, so both callers share it.
Slicing in the model's own units and transforming afterwards would agree with
this only for something upright and uniformly scaled, and would have needed a
second case for everything else — two implementations of a hitbox, drifting.

**Transforms are walked up rather than read from `global_transform`.** That one
needs a scene tree and answers with the local transform alone without one, so
every shape on a map built in code would have been measured correctly and placed
at the origin. Section 10 asks the world to be testable with no engine in the
loop; this is part of what that costs.

**The grass stopped guessing.** A prop's clearance was its bounding box, so a
tree cleared a square of lawn as wide as its crown. It is sliced at blade height
now, like a painted model. Three things fell out of having a height where a box
had none: a canopy lets the lawn grow under it, a model standing at floor level
is finally cleared around at all, and a hidden model stops counting.

**Cost, measured rather than asserted.** On the tile pack's own models, about
3 ms per prop to derive and, at two hundred props, 0.7 ms per `blocked_at`. The
first is a load cost and cacheable. The second is the one that grows without
bound: there is no spatial index, so the walker tests every shape on the map on
every move. Neither is a problem at the size maps are now, and both are written
down here so that the first one that bites is recognised rather than rediscovered.

**Props do not nest.** A prop's shape is built from every mesh below it, so a
prop inside a prop would hand the walker two copies of the same wall. The outer
one owns everything under it, which also makes an inner one's flag meaningless —
a trap, and one the validator can report.
