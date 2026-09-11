# 0064 — Leaves are sown, and shaded as the branch

**Status:** Accepted — the generator; **pending** — the wiring into the builder
**Date:** 2026-09-11
**Builds on:** decisions 0062 and 0063
**Recorded in:** spec 16, section 9

## Context

The maintainer pointed at Laure De Mey's Unity foliage tool (80.lv, *An Awesome
Foliage Scattering Tool for Unity*) and asked for the same thing here. The public
description is the whole of what exists — there is no code published, so this is
reproduced from described behaviour and nothing enters the repository.

Read carefully, that tool is **not a shader**. It is a mesh generator plus a small
billboard shader that reads what the generator baked. Five parts:

1. points sown over a source mesh's surface, one card each
2. the surface's **normal**, the **lightmap** and the **colour** baked per card
3. a shader turning each card partly to the camera and partly to the normal
4. three densities generated, cross-faded by distance
5. a leaf texture carrying several leaves, so fewer cards buy the same density

## Decision

**Sow leaf-shaped polygons, and give every one of them the normal of the surface
underneath.**

That second half is the whole idea, and it is the part worth copying exactly. A
leaf shaded by its own normal catches its own tone; a thousand of them catch a
thousand tones and the bush reads as a heap of independent flakes. Shaded by the
normal of the ball they grew from, they read as one ball covered in leaves.
Everything else in this file is bookkeeping around that sentence.

**Three of the five parts are deliberately absent**, because the problems they
solve do not exist in this engine:

| part | why it is not here |
| --- | --- |
| bakes the lightmap per card | our look is `unshaded` and shades per fragment from the normal (0062), so writing the support's normal gets the same result with nothing baked |
| turns cards towards the camera | our overworld camera is a fixed world offset and never yaws — there is nothing to track |
| cross-fades three densities | that is for an open scene with a free camera; ours sits at a fixed distance and sees a few metres |

### A polygon, not a textured card

Her cards are quads with an alpha-cut leaf texture: two triangles, the cheapest
possible. Ours is a six-point teardrop, four triangles.

The reason is that **this world has no textures at all** — not one asset carries
one. An alpha card would cost a third shader (`cull_disabled` plus alpha scissor),
transparency sorting, and a leaf texture to author, and it would be the first
textured thing on screen. The shape is paid for in geometry instead, where it
costs none of those.

### Variants, because an item is stamped

A `GridMap` paints one item over many cells. A single sowing would be fifty trees
identical leaf for leaf — the repetition decision 0063 removed from the ground,
back at a far more visible scale. The builder will produce several sowings per
item as separate palette entries, painted by hand, rather than a runtime that
generates per cell. The bare item is kept and keeps its id.

### Only the surface that is the foliage

The first render settled this: sown on every surface, a palm's **trunk grew brown
leaves** and read as a diseased tree.

The measurement separates foliage from structure cleanly — the palm's canopy is
125.7 against its trunk's 20.7, the cactus's body 23.3 against its spines' 1.2 —
so a surface is sown only if it is at least half the area of the largest. A
threshold and not a rule, because a rule guessed from geometry is a rule nobody
can correct; at zero every surface is sown again.

## Consequences

**Density is per square unit of the mesh's own space, not per game metre.** A
`GridMap` draws an item at `ART_SCALE`, so these models are authored about twice
the size they appear at, and a density in metres would be wrong by four on every
one of them. The first sweep produced 17,565 leaves on one palm for exactly this
reason.

**A sown palm roughly doubles: 377 leaves, 2,262 vertices onto 2,405.** Cheap for
a handful of trees and not obviously cheap for a forest. `tools/budget/` is where
that gets answered, and it has not been asked yet.

**Not yet wired into the tile library.** The builder and the dock were being
changed in the working tree at the time — a roughcast feature, with its own new
parameter on `build` — so the generator is landed on its own rather than risking
somebody else's work in progress. What remains is small and already has a shape to
follow: a `foliage` fragment beside `parting` and `rough`, matched with the same
helper, calling `VltFoliage.sown` once per variant and adding each as an item.

**Nothing is asserted about how it looks.** The tests cover the two properties
that are not visual — that a seed is repeatable, so a rebuild cannot quietly
redraw a painted map, and that every leaf carries the support's normal. The look
is looked at, the way the grass is (decision 0059).
