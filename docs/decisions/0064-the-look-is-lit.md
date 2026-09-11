# 0064 — The look is lit

**Status:** Accepted
**Date:** 2026-09-11
**Supersedes:** decision 0062's `unshaded` rule, and only that. The rest of 0062 —
one shared look, the wind kept out of it, two shaders because `render_mode` is per
shader — stands unchanged.
**Recorded in:** spec 16, section 9

## Context

Decision 0062 made every surface in the game `unshaded` and had it light itself
from a direction uniform. The stated reason was that **Godot's `light()` stage has
no screen coordinates**, and the screentone has to be laid out in screen space
against the same value that picks the tone.

That reason is false. `FRAGCOORD` and `SCREEN_UV` are both in scope in `light()`;
a four-line shader that uses them compiles. The whole of 0062's lighting argument
rested on a claim nobody had tested, and the price was every cast shadow the game
might have had.

It is worth being precise about what that cost. The pack's own marketing renders
use the same one-colour-per-surface models this project does, and they read well
because every tree throws a shape across the ground. Decision 0063 paid part of
that bill by hand — a drawn contact band, a world grain — while noting that "a
part of the flatness is a cost that decision imposed". This is the rest of the
bill, and it is paid by removing the cause.

## Decision

**Every surface is lit. `ATTENUATION` carries the cast shadow, and the same maths
that draws a dark side draws a thrown one.**

A thrown shadow and an attached one are deliberately **not** two visual languages:

- the thrown shadow is snapped from the shadow map's filtered gradient back to a
  hard edge, so it is a *shape* an inker could have drawn rather than a soft patch
- it is filled with the same coarse screen, at a constant density, because a
  thrown shadow is a flat area of tone — the modelling is done by the surface it
  falls on, not by the shadow
- it reaches the first shadow step, never the core. The core is attached shading:
  it describes a form turning away, which a thrown shadow says nothing about
- it gets the same stroke along its own edge that the terminator gets. That one
  detail is most of what makes it read as drawn

### ALBEDO is white

**Measured on this project's renderer, which is Forward Mobile:** whatever
`light()` leaves in `DIFFUSE_LIGHT` is multiplied by `ALBEDO` afterwards. An
albedo of pure red under a pure white light comes out pure red.

That rules out the obvious shape. A multiply can only darken a channel, and this
look needs a shadow that *cools and saturates* — a yellow body's shadow leans
violet, which no multiply can reach. So the surface declares itself white, the
paint is rebuilt inside `light()` from varyings, and what is written to
`DIFFUSE_LIGHT` is the finished colour. Multiplying it by white changes nothing.

The cost is that the paint is computed once per light rather than once per pixel.
With one sun that is the same work as before.

### One sun, and lamps add to it

The directional light writes the printed surface. Every other light — a lantern, a
window, a fire — **adds** a warm stepped pool and never re-shades anything.

That is both right for the medium, where a page has one key and local glows, and
the only way accumulation stays sane: two lights each writing a base would count
the shadow tone twice. It follows that **a scene needs exactly one
`DirectionalLight3D`**, and that a scene with none renders black rather than dim.
`Daylight` is the rig that supplies one, along with the paper behind it, and it
exists so that two scenes cannot disagree about what time of day it is.

### The exposure came down with it

`comic-manga` set `saturation` to 1.25 and the shared look defaulted to 1.34. Both
were tuned against a pass where nothing was ever fully lit. Under a real sun the
same numbers read neon, because a fully lit fill now really is the paint at full
strength. Swept at 1.25/1.0, 1.05/0.88 and 0.92/0.80 against a dressed scene:
**1.05 with the sun at 0.88** is where the greens stop being neon and the shadows
still carry. The shared default came down to 1.08 for anything with no preset.

## Consequences

**Four shaders that were not mine had to be ported.** The turf, the turf mat and
the foliage leaf were written against the unshaded API during this same session
and are built on the shared include. Leaving the include rewritten and them broken
was not an option, so they were carried over: `render_mode` loses `unshaded` and
`shadows_disabled`, the paint each of them builds moves into its own `light()`,
and the turf's per-blade normal is written to `NORMAL` in `vertex()` instead of to
a world-space varying the old path read. Their intent is unchanged and none of
their own decisions were touched.

**Varyings are assigned by each shader, not by a helper.** The language forbids
writing a varying anywhere but inside `vertex()`, which is the second time that
rule has bitten this file. The include offers `comic_point` and `comic_up`, and
the four assignment lines belong to the caller — which is also what lets the grass
and the foliage hand over the *moved* vertex after they displace it.

**Shadow acne is the standing risk.** These models are flat-shaded and the ground
is a single plane many cells wide, which is exactly the case that stripes itself.
Snapping the shadow edge makes acne worse, not better, because no filter is left
to smear it. `Daylight` carries the bias values that hold, and a model that starts
striping is a bias question before it is a shader question.

**The battle screen has a sun again**, and it comes from behind the camera so that
a creature's face reads. What `key_follows_camera` used to do by rotating the key
with the viewer is now done by placing the light — which is the same intent,
expressed where a scene can see it.
