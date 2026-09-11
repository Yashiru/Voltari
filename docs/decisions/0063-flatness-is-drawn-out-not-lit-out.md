# 0063 — Flatness is drawn out, not lit out

**Status:** Accepted
**Date:** 2026-09-11
**Builds on:** decision 0062 — the shared look is where both of these live
**Recorded in:** spec 16, section 9

## Context

The quarantined pack, and the pack the maintainer was considering buying, read as
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

**Two layers in the shared look, both off by default, both raised on the world
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

## A third layer was built and taken back out

A **cavity** term — how open each corner is, baked into the mesh's colour channel
at library build time and read by the shader — was written, looked at and removed
the same day, on the maintainer's call. It is recorded rather than deleted because
two things learned building it outlive it.

**Never rewrite a model file to add data to it.** The cavity was originally to be
baked in Blender. It was not, because **every route that rewrites an FBX damages
these files**, and both were tried and measured during the same week: FBX to FBX
divides the model by a hundred, since Godot renormalises on the unit header and
the scale compounds; FBX to glTF keeps the scale but bakes a second axis
conversion, and the tile comes into the library lying on its side. Anything a mesh
needs is computed on the mesh Godot already imported.

**Godot splits a vertex wherever the shading breaks.** On a flat-shaded model a box
corner is three or four separate vertices, each knowing only the triangles of its
own smoothing group. Any per-vertex measurement of shape has to weld by position
first — measured unwelded, the pass returned white everywhere and looked like it
had worked.

## Consequences

**One metric was abandoned.** "Pixels identical to both neighbours" went 30.2 % to
29.4 % across the change and says nothing, because a snapped grain *creates* flat
patches by design. Distinct colours over the same frame went 4 153 to 6 822, which
is the number that tracks what the eye reports. Both figures are from the frame
with the cavity layer still in; grain and contact alone account for the smaller
share of it.

**Emptiness is not addressed and is not a shader problem.** The densest thing in
the pack's renders is the decoration, and a test map that is an empty field will
read as flat with every layer above turned up.
