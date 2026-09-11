# 0064 — Leaves are sown, and shaded as the branch

**Status:** Accepted
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

### Nothing has foliage until somebody says so, cell by cell

The first plan was a name fragment in the dock, applied to the whole palette on
every rebuild — the shape the grass already uses. **The maintainer rejected it**:
foliage is to be added where they want, when they want, configured at the moment
it is applied, and on nothing at all by default.

So there is no automatic pass and nothing to match. A `VltFoliagePatch` node is
one application: a list of cells, the settings used, and a seed. Its settings are
`@export`s, so they belong to that application and to no other — sowing a second
selection makes a second patch, and either can be tuned or deleted without
touching the other. Deleting one takes its leaves and leaves the models bare.

Godot exposes `GridMapEditorPlugin.get_selected_cells()`, so the cells are the
ones the author already selected with the tool they already use. Reaching the
plugin instance is the part that is *not* offered — `EditorInterface` exposes only
`is_plugin_enabled` — so it is found by searching the editor's tree, and says so
plainly when it cannot be.

**A patch stores cells and numbers, never a mesh.** Six floats and a list of cells
go into the `.tscn` and the leaves are grown again on load, which is only sound
because the sowing is deterministic. The seed is the cell's, not the item's: two
cells of the same palm are never the same tree, and a cell keeps its tree when its
neighbours change.

**Only the leaves.** The `GridMap` still draws the bare model underneath, so a
patch adds foliage rather than replacing a tree with a sown copy of it. That is
also what makes it removable without leaving a hole.

### A leaf is drawn from both sides

The look culls back faces, and a leaf is a flat shape. Sown one-sided, half a
canopy vanishes the moment the camera passes behind it — reported from the editor
as *les feuilles sont visible que d'un côté*, and it is exactly that.

Each leaf's fan is therefore wound twice, once each way. **It costs indices and no
vertices**: the six points are shared and four triangles become eight. Both sides
carry the same normal — the support's — so they shade identically and there is no
seam to see.

### A cell's orientation is part of its placement

A `GridMap` cell stores an item **and one of twenty-four orientations**. The mesh
is sown in its own space, so leaves placed against an identity basis stay in the
model's untouched pose while the grid draws the model turned — foliage crossways
to the thing it grew on, which is what the maintainer reported and correctly
guessed the cause of.

The reason it survived every render made here is that **none of them had turned
anything**: on an unrotated cell the two poses agree exactly. A test now paints
one cell upright and one turned a quarter, and holds that the turned cell's leaves
are the upright cell's rotated about the cell's own centre.

### Only the surface that is the foliage

The first render settled this: sown on every surface, a palm's **trunk grew brown
leaves** and read as a diseased tree.

The measurement separates foliage from structure cleanly — the palm's canopy is
125.7 against its trunk's 20.7, the cactus's body 23.3 against its spines' 1.2 —
so a surface is sown only if it is at least half the area of the largest. A
threshold and not a rule, because a rule guessed from geometry is a rule nobody
can correct; at zero every surface is sown again.

## Consequences

**A leaf's length is a share of the model, not a length.** Set as an absolute size
it was right for exactly one model: tuned on an eight-unit palm, it put leaves a
third the height of a three-unit cactus on it, each sticking far outside the volume
it grew on. Reported from the editor as foliage applied *perpendiculairement* to
the mesh rather than on it — which is what a leaf far larger than the curvature it
sits on looks like. A share of the model's own height suits a palm and a cactus
with one number.

**Density is per square unit of the mesh's own space, not per game metre.** A
`GridMap` draws an item at `ART_SCALE`, so these models are authored about twice
the size they appear at, and a density in metres would be wrong by four on every
one of them. The first sweep produced 17,565 leaves on one palm for exactly this
reason.

**A sown palm roughly doubles: 377 leaves, 2,262 vertices onto 2,405.** Cheap for
a handful of trees and not obviously cheap for a forest. `tools/budget/` is where
that gets answered, and it has not been asked yet.

**The generator is runtime code, not map tooling.** It moved out of the addon into
`game/presentation/world/`, because a patch regrows its leaves on load and the
game cannot depend on an editor plugin. The tile library is untouched — which also
kept this clear of a roughcast feature being written in the same files at the same
time.

**A map pays for its foliage at load.** Regrowing is a few milliseconds per
hundred sown cells and the scene stays small. The alternative, baking the mesh
into the `.tscn`, trades kilobytes for megabytes and was not taken.

**Nothing is asserted about how it looks.** The tests cover the two properties
that are not visual — that a seed is repeatable, so a rebuild cannot quietly
redraw a painted map, and that every leaf carries the support's normal. The look
is looked at, the way the grass is (decision 0059).
