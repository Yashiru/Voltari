# 0074 — Six looks, one shader

**Status:** Accepted
**Date:** 2026-09-11
**Renumbered:** written as 0066, which decision 0066 (one turf boundary) already
held. Text older than this repair cites it as 0066.
**Builds on:** decision 0073 — being lit is what let the other five join
**Recorded in:** spec 16, section 9

## Context

`toon`, `bd`, `vinyl`, `ramp` and `typelit` were separate creature shaders. The
look control offered all of them and the maintainer reported that picking one did
nothing. It was right to fail — it just failed silently — and two things stopped
them:

- **none declared a flat `albedo` colour**, only a texture, and the world's models
  carry their colour in their material with no texture at all. A tile wearing one
  would have come out white
- **`bd` was `unshaded`** and lit itself from a direction uniform, so a world
  wearing it would have lost every cast shadow decision 0073 went to get

The other four turned out to be lit already, and already writing
`DIFFUSE_LIGHT += ALBEDO * ... * tint` — the same composition 0073 measured. They
were much closer to the world than anyone had noticed.

## The shape of the problem

The world reaches the screen through **five shaders** — `comic`, `grass_parting`,
`turf`, `turf_mat`, `foliage_leaf` — which differ only by `render_mode`. A blade
of grass draws from both sides, a crate does not, and `render_mode` is per shader
and not per material.

So a look per shader is **thirty files**, each a copy of the same maths, and they
would drift within a month. That is not a trade-off; it is a dead end, and it is
the whole reason the answer below is the one it is.

## Decision

**A look is a mode of the shared look, not a shader of its own.**

`look_mode` selects among six branches inside `comic_look.gdshaderinc`. The five
world shaders are untouched: they call `comic_shade` as before and inherit every
look for free. A branch on a uniform is coherent across a draw call and costs
nothing measurable.

Each look is a pure function of what it is given — paint, normal, light, shadow,
pixel — and returns a finished colour. None writes a built-in. That is what lets
six live in one shader without any of them having to know the others exist.

**Every one of them now takes `shadowed`**, so five looks that never had a cast
shadow have one. `bd` gains the most: it was the only self-lit one left.

The five standalone shader files are **deleted**. Keeping them would have been two
implementations of each look, which is the defect this project names first.

### What changed in porting, and what did not

The maths of each look is unchanged. Three things about its surroundings are not:

- **They share `saturation` and `lift`** with `comic` rather than keeping their
  own. The paint is one question, not six — a look is how a surface is *shaded*,
  and a surface that changed colour as well would make the two impossible to judge
  apart.
- **Emission became addition.** `toon` and `typelit` drew their rim as `EMISSION`,
  which the engine adds after the light. On a surface that declares itself white
  adding it to the returned colour comes to the same thing, and it keeps each look
  a single function.
- **Every look-specific uniform is prefixed.** `wrap` belonged to four of them
  with four different defaults; `shadow_tint`, `ground_shade`, `terminator`,
  `rim_*` and `crease_*` each belonged to two or three. In one shader they would
  have collided, so they are `toon_wrap`, `vinyl_wrap`, `bd_terminator` and so on.

### Two defects the port exposed

**A rim is not a grazing angle.** `1 - dot(N, V)` reaches one wherever a surface
is seen edge-on. On a creature that is the silhouette; on a ground plane it is
half the visible area, and the far side of the world washed white. Both rims are
now gated by how fast the normal is turning — a normal that is not turning is not
an edge — through a shared `rim_turn`.

**A sampler with no texture is not a look.** `ramp` reads its entire light
response off a strip, and only the creature runtime ever bound one. Everywhere
else the sampler fell back to white and the look rendered with no shading at all,
which reads as broken rather than as a choice. `Look.wear` binds the strip.

## Consequences

**A style names a mode, not a file.** `CreatureView.mode_of` resolves a style —
through a preset's `shader` field where there is one — and it is static and shared
so the creatures and the ground cannot end up in different looks. The creature
runtime loads one shader now and sets the mode on it.

**This is in tension with spec 16, section 9**, which settled the art direction as
the comic look and called the others alternatives. That still stands as the
direction: the game wears comic-manga. What changed is only that trying another
one is now a click instead of an impossibility, which is what the maintainer asked
for and what a search for a look needs.

**`toon` and `vinyl` are dark on a world.** Both take their shadow side to near
nothing, because they were tuned on creatures lit from a chosen direction with
nothing behind them. Under a real sun with no ambient, an away-facing wall goes
black. Their numbers are on the control's sliders; no floor was added, because
adding one would change what each look *is* rather than where it is used.
