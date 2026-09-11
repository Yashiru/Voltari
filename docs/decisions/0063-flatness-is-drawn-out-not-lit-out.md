# 0063 — Flatness is drawn out, not lit out

**Status:** Accepted
**Date:** 2026-09-11
**Builds on:** decision 0062 — the shared look is where all three of these live
**Recorded in:** spec 16, section 9

## Context

The placeholder pack, and the pack the maintainer was considering buying, read as
flat. The request was a shader that adds irregularity to the textures.

Measuring first changed the question:

```
Grass_Tile_B1   2 surfaces  1192 sommets  UV NON   couleurs-sommet NON
GrassB          1 surface    202 sommets  UV oui   couleurs-sommet NON
PalmTree1       2 surfaces  2405 sommets  UV oui   couleurs-sommet NON
```

**No model carries a vertex colour, and the ground tile carries no UVs at all** —
the one surface most in need of breaking up is the one no UV-space technique can
reach. There is nothing to recover and nothing to map.

The pack's own marketing renders settle what actually reads as flat. They use the
same one-colour-per-surface models and they look fine, because every tree casts a
shadow and every corner is occluded. Decision 0062 made the game `unshaded`, so
neither exists and neither can. **A part of the flatness is a cost that decision
imposed**, and it is paid here rather than by reopening it.

Four causes, and texture irregularity is only one:

| cause | corrected by |
| --- | --- |
| no contact, no occlusion | drawn rather than computed |
| one colour per surface | a grain |
| repetition — 121 identical tiles on an 11×11 floor | a pattern that ignores tile edges |
| emptiness — the renders are densely decorated, a test map is a field | level design, no code |

## Decision

**Three layers in the shared look, all off by default, all raised on the world
only.**

**Grain** — a world-space noise snapped to three tones, multiplied into the fill.
World space is not a preference: the ground has no UVs, and a world-space pattern
crosses a tile boundary without a seam, so a hundred identical tiles stop reading
as a hundred identical tiles. Snapped rather than smooth, because a gradient over
a flat fill is the polish this look exists to avoid; patches of flat tone are what
a screentone is. Swept at 0.14 and 0.26, over 2.6 m and 4.5 m, and looked at —
0.26 over 4.5 m is where the patches read as variation rather than as dirt.

**Contact** — a stepped band where a model meets the ground, its edge one screen
pixel wide from the same derivative the terminator uses. Measured up the model's
own height, not from a world height: anything painted on a second layer would
otherwise get its band in mid-air.

**Cavity** — how open each corner is, written into the mesh's colour channel at
library build time and read by the shader. **This is not ambient occlusion and
does not pretend to be**: it knows nothing about the rest of the scene or even the
rest of the same model, so a trunk under its own canopy gets nothing. It knows
where a model folds into itself, which on low-poly work is most of what occlusion
buys.

Cavity is the one layer that is not stepped. The ban on smooth ramps is about a
gradient across a broad fill; a fold is narrow by definition, so its falloff reads
as a drawn line thickening rather than as a sheen.

## Why the cavity is computed in Godot and not baked in Blender

The maintainer first chose a Blender bake. It was not taken, because **every route
that rewrites an FBX damages these files**, and both were tried and measured
during the same week:

- **FBX to FBX** divides the model by a hundred. Godot renormalises on the unit
  header, so a scale factor is applied to the mesh *and* to the header and the two
  compound.
- **FBX to glTF** keeps the scale but bakes a second axis conversion, and the tile
  comes into the library lying on its side.

Both were reverted. Nothing here touches a model file: the pass runs on the mesh
Godot already imported, inside the tool that already writes its materials, and
costs 174 ms for all ninety-two items.

**Welded by position first.** Godot splits a vertex wherever the shading breaks,
so on a flat-shaded model a corner is three or four separate vertices, each
knowing only the triangles of its own smoothing group. Measured unwelded, a box
corner has no neighbours across the edge and reads as perfectly flat — the pass
would have returned white everywhere and looked like it worked. The normal is
recomputed from the welded triangles for the same reason: a flat-shaded normal
describes a face, and what is wanted is the shape of the surface.

## Consequences

**The mesh now carries data, so the library is no longer only a copy of the
folder.** Rebuilding is still safe and ids still never move, but a mesh is
rebuilt to add the colour channel — which means blend shapes and levels of detail
would be dropped. No item has either; the first one that does will need this
revisited.

**One metric was abandoned.** "Pixels identical to both neighbours" went 30.2 % to
29.4 % across the change and says nothing, because a snapped grain *creates* flat
patches by design. Distinct colours over the same frame went 4 153 to 6 822, which
is the number that tracks what the eye reports.

**Emptiness is not addressed and is not a shader problem.** The densest thing in
the pack's renders is the decoration, and a test map that is an empty field will
read as flat with every layer above turned up.
