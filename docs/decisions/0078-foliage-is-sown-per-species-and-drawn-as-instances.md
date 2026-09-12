# 0078 — Foliage is sown per species and drawn as instances

**Status:** Accepted
**Date:** 2026-09-12
**Refines:** decision 0064 (leaves are sown and shaded as the branch)
**Recorded in:** spec 16

## Context

The target is hundreds of trees under dense foliage, on a phone. The density
itself is not negotiable: reducing it is the one lever that would fix the
symptom which is not the problem, and the maintainer ruled it out.

Measured on a six-metre fir, at the density a patch ships with:

| | one tree |
|---|---|
| leaves | 21 234 |
| triangles | 169 872 |
| geometry | 6.8 MB |
| generation | 55 ms |

`tools/budget/tiers.json` guesses 150 000 triangles for a five-year-old phone
and 1 000 000 for a flagship, for the whole scene. **One tree exceeds the low
tier.** A hundred trees at a *tenth* of the shipped density come to 1 698 400
triangles, 100 surfaces, 680 ms of generation — and at the real density, roughly
17 million triangles and 680 MB.

## What the turf already proves

The same repository draws grass the other way round, and the comparison is the
whole argument. At a comparable triangle load:

| | turf, 100 cells | foliage, 100 trees |
|---|---|---|
| triangles | 1 400 000 | 1 698 400 |
| draw calls | **1** | 100 |
| geometry in memory | **0** | ~68 MB |
| CPU at load | **0 ms** | 653 ms |

A blade is nine vertices and seven triangles and exists **once**; `TurfPatch` is
a `GPUParticles3D` whose process shader works out where each blade stands from
its own index. Nothing is built on the CPU and nothing is stored.

So it is not the triangles. It is everything around them, and the foliage does
each of those the expensive way: real geometry per leaf, merged per cell, a
surface per cell, and — on any model the tile library has dressed — a duplicated
material per cell.

## Decision

**Leaves are baked per species, not per cell**, in three to five variants, and a
tree draws one of them. Two trees of one species share their scatter; the brush
already turns each prop by a random angle, which is what keeps the repetition
from reading.

**The scatter is a table, not geometry.** Position, normal, size and tone per
leaf, written once per variant — about 680 KB, against 6.8 MB per *tree* today.

**A leaf is drawn as an instance**, the vertex shader reading that table by
instance id. The turf derives a blade's place from arithmetic because it scatters
on a plane; a leaf sits on an arbitrary surface and carries its support's normal,
which no index can produce. A shared table is the same idea with the arithmetic
replaced by a lookup.

**Each tree stays its own visual instance.** Not one batch for the whole forest,
which was the first proposal and is wrong: a single batch is submitted whole, so
the engine can no longer drop a tree that is off screen. Culling comes first —
forty visible trees are forty draw calls, which costs nothing, and the other
two hundred and sixty cost nothing at all.

**A leaf is wound once, with `cull_disabled`.** It is wound twice today, on the
stated grounds that `cull_disabled` "would draw every leaf four times". That is
not what it does: it rasterises each triangle once and accepts either facing.
Winding twice submits two triangles and throws one away — twice the geometry for
an identical image. The camera is top-down and fixed, so the underside of a leaf
is never the side being looked at.

## Options rejected

**Reducing the density.** Ruled out by the maintainer, and the measurements agree
it was aimed at the wrong thing.

**Keeping a sowing per tree.** What costs the 6.8 MB. Rejected, and recorded here
so the loss of per-tree uniqueness is a decision rather than something that
happened.

**Impostors at distance now.** The technique `foliage.gd` says it left out "until
something is measured that asks for it". Something has now measured it, but
culling comes first and the camera is top-down over a close view — the maintainer
reports little foliage on screen at once. Built only if a measurement on a device
asks for it, which is decision 0048's rule applied to ourselves.

**One draw call for the whole forest.** Elegant, and incompatible with culling.
Stated because it was proposed and withdrawn for a reason worth keeping.

## Consequences

Memory stops scaling with the number of trees and starts scaling with the number
of species. Load time stops scaling with the map and starts scaling with the
palette.

**Two trees of one species and one angle are identical, leaf for leaf.** That is
the price of the variants being finite, and three to five with a free rotation
makes it hard to catch. It is still true.

The reserve levers, unused and written down so they are not rediscovered:
impostors by distance, dropping leaves that face away from a camera that never
moves, and a compressed vertex format.
