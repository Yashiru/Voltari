# 0068 — The edge of the grass is measured on a grid, not counted in cells

**Status:** Accepted
**Date:** 2026-09-11
**Supersedes in part:** decision 0066 — its boundary, its wander and its "the
blades cut, the ground fades" all stand; only *where the patch edge is measured*
changes
**Recorded in:** spec 16, section 12

## Context

The maintainer asked for a brush: paint turf freehand rather than select cells and
press a button. The brush is not the hard part. What a patch can *describe* is.

Decision 0066 gave a patch two boundaries, both distances in metres, and they were
measured two different ways. The ring around an obstacle was a distance field on a
grid. The edge of the patch was worked out per corner of each cell, in cells, and
handed to the blades in a texture and to the mat in a vertex attribute.

**A boundary measured in cells can only ever run along cell walls.** No amount of
brush would change that: a stroke painted through the middle of a cell has nothing
to write itself into.

## Decision

**Both boundaries are measured the same way, on the same grid.**

The field gains two channels: how far inside the grass a texel is, and how far
outside. One of them is always zero, so their difference is a signed distance and
its sign is which side of the edge this is — which is how an eight-bit texture
carries a negative. A blade reads it at its own feet exactly as it already read
the room around an obstacle.

What goes away: the per-corner measurement, the point-to-square distance it needed,
the dictionary of corners it cached, the second row of the spots texture, and the
bilinear interpolation the blades did across their own cell. Around ninety lines,
and one of two ways of saying the same thing.

### And the field halves in resolution

Sixteen texels a metre becomes eight — twelve and a half centimetres. Three
distance transforms on the coarser grid cost less than one on the finer, and the
patch is rebuilt **once** rather than once for the blades and again for the mat,
which nobody had noticed.

Measured on the maintainer's own map, a 625-cell patch: **252 ms to 95 ms**, and
the obstacle rings still cover **103.4 m²** — the same number to a tenth, at half
the resolution. That is the check that the boundary did not move.

It matters because a brush rebuilds on every stroke.

## What it costs, stated

A chamfer measures from texel centre to texel centre. Half a texel is taken off
every distance, which makes a straight edge exact, and **a convex corner still
comes back up to half a diagonal texel long** — under a tenth of a metre, at
corners only. The wander of decision 0066 moves the boundary by more than that on
purpose.

That error is measured against an analytic square, and the square is what is on
its way out: once the mask is painted, the texel grid *is* the shape, and there is
no squarer answer to be closer to.

## The mat has not moved yet

The mat still receives its distance per vertex, in its second UV set — but that
number is now **read out of the field** rather than computed a second way, so the
two agree by construction. It interpolates it across a whole cell, which is right
for a boundary that runs along cell walls and will not be once one can be painted.

It stays that way for one reason only: `turf_mat.gdshader` is open on the
maintainer's desk for an unrelated change. Moving it is the first thing the next
step does, and `turf_edge.gdshaderinc` carries both readings until then, the
older of the two marked as what it is.

## Rejected

**Keeping both measurements and letting the brush write cells.** It is what the
cell-granularity brush would have needed and the maintainer asked for the other
one. Two ways of measuring one boundary was already the thing that made adding a
wander to it hard (decision 0066); carrying it further to avoid a refactor would
have been paying the interest and never the debt.

**An exact Euclidean transform instead of a chamfer.** It is O(n) and available,
and it would not help: the error above is in measuring to texel *centres*, which
an exact transform does too.
