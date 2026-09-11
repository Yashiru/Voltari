# 0066 — One turf boundary, measured once and wandered once

**Status:** Accepted
**Date:** 2026-09-11
**Builds on:** decision 0065 — the roughcast this reuses rather than reinventing
**Recorded in:** spec 16, section 9

## Context

A patch of turf is drawn by two shaders that never meet. `turf_scatter.gdshader`
places blades on the GPU; `turf_mat.gdshader` rasterises the dark ground between
them. Both have to stop at the same place, and there are two places to stop: the
edge of the cells somebody sowed, and the ring around anything standing on them.

The maintainer asked for the edges to stop being perfect. They were: a straight
line along a row of cells, a perfect offset around a post. A boundary computed
from a distance field *is* a perfect curve, and perfect is the tell.

## Two mechanisms for one boundary, and only one of them could wander

The ring was already a distance — a field the two shaders both sampled. The patch
edge was not: it was a **coverage** baked into the mat's vertex colours, how many
of the four cells around a corner had been sown, and the blades had no equivalent
at all. They simply existed inside sown cells and stopped at the cell wall.

That asymmetry is what made the feature request hard rather than a one-line noise.
Displacing a coverage the mat holds and a cell wall the blades hold would have
moved two different lines by two different amounts, and the gap between them is a
dark halo around the grass — the exact defect the shared field was introduced to
remove.

## Decision

**Both boundaries are distances in metres, both are measured once, and one noise
displaces both.**

- Each corner of the sown area is measured once — not once per cell touching it —
  and the number goes to the mat in its second UV set and to the blades in a
  second row of the spots texture. A blade interpolates the four corners of its
  cell exactly as the rasteriser interpolates them across the mat's quad, so the
  two arrive at the same distance at the same point.
- `turf_edge.gdshaderinc` holds the noise, the field and both boundary functions,
  and is included by the scatter and the mat. A particle shader cannot include
  the shared look — no fragment stage, no `varying` — so the turf carries its own
  two-dimensional noise under its own name, which also keeps it from colliding
  with `noise31` in the mat, which includes both files.
- The wander is a **bite in metres**, signed, subtracted from whichever distance
  is being tested. Keyed on world position, so two patches sown separately share
  one wander and the seam between them does not draw itself.

### The bite fades out as the room does

Against an obstacle the bite is scaled by how much room there already is. Without
that, a negative wander would push a blade *inside* the thing it is keeping away
from — grass growing through a fence post, from a feature meant to make the edge
prettier. The boundary can move freely in the open and cannot move at all against
the object itself.

### The blades cut, the ground fades

Unchanged from before and worth restating, because it is the thing that keeps
being re-proposed: the grass **stops**, and only the darkened ground under it
softens. Thinning the blades over the last stretch makes a lawn read as half-mown.
The wander can therefore only eat into the patch edge — there are no blades
outside the sown cells for it to hand back — so the border sits a centimetre or
two inside a straight edge. That is the trade, and it is the right way round.

## What this fixed on the way

Measuring to the **middle** of the nearest bare cell and subtracting half a cell
is right for the midpoint of an edge and wrong for a corner, which is 0.71 cells
from that middle and 0 cells from the bare ground itself. Every outside corner of
every patch therefore read as a fifth of a cell inside the grass: the fade never
reached the tile's own colour, and no wander small enough to be tasteful could
reach a boundary it believed was somewhere else. It is now a distance to the bare
cell's **square**. A test pins it.

## Rejected

**A second distance transform for the patch edge.** The obvious way to give the
blades a patch-edge distance was to stamp the unsown area into the same chamfer
pass that measures the obstacles. It is a second sweep over the field, which on
the maintainer's own patch is two more passes over 666,000 texels in GDScript on
every slider drag. The corner measurement is a few thousand cells and interpolates
to the same answer.

**Noise on the room field at build time.** Perturbing the stamped field would have
wandered the ring and left the patch edge perfect, and it would have been baked —
so tuning the amount meant rebuilding the field. In the shader it is one hash per
fragment and free to change.
