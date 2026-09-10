# 0059 — The grass shader is looked at, not asserted

**Status:** Accepted
**Date:** 2026-09-10
**Refines:** decision 0055 (a creature is never still)
**Superseded in part by:** decision 0060 — the harness and the method stand; the
deformation this describes was reversed
**Superseded in part by:** decision 0061 — the per-cell variation was reversed
too, for the opposite reason: it was reasoning about a still field
**Recorded in:** spec 16, section 12

## Context

Every other piece of this engine is judged by a test. A shader is not: no
assertion distinguishes grass that moves from grass that moves *well*, and the
difference is the whole of the work.

The first version bent grass around a walker and stopped there. Asked to make it
good, the honest problem was not knowing what it looked like.

## Decision

**A rendering harness, and a contact sheet.** `tools/grass/preview.gd` lays real
grass on the grid new maps use, walks somebody through it, and writes four kinds
of frame:

| Frame | The question it answers |
|-------|-------------------------|
| `still` | is the field alive, and varied, or does it breathe as one animal? |
| `walk_NN` | how does it read from the angle the game looks at the world? |
| `wake_NN` | is there a trail behind somebody moving? |
| `top_off` / `top_on` | what exactly does the walker change? |

The last is a **pair on purpose**. A footprint is obvious in the difference
between two frames and easy to imagine into either one alone.

**Every claim about how this looks was checked against a render**, and three of
them were wrong when it was. The shader is tuned against images, not against
argument.

## What the shader does, and why each part is there

- **The blade rotates about its root**, keeping its length. Adding an offset to
  the tip stretches the blade, and the difference shows the moment a bend is
  large enough to notice.
- **The normal turns with the geometry**, by the same rotation, built with
  Rodrigues. Nudging the normal toward the bend is the usual shortcut and it
  drifts wrong exactly when the bend is large.
- **Nothing is in phase.** Phase, stiffness and shade come from a hash of where
  the blade's root is in the world.
- **Every cell is turned and resized** by a hash of its own origin. A `GridMap`
  draws the same mesh at every cell and the eye finds the repetition in about a
  second; this was the loudest tell and it cost one hash to remove.
- **Two lagged centres make a wake.** The gap between them is grass just stepped
  off: still down, and ringing as it comes back up. It is a lag, not a memory —
  nothing records where anybody has been.
- **A pressed blade gives up the wind** and darkens. Two forces added make a
  footprint look like a coincidence rather than a weight, and grass in a
  depression is grass in its own shadow.
- **Each item carries its own hinge and height**, written by the tile library
  builder from the mesh's own bounds. The grass in the placeholder pack runs from
  0.55 m to 3.4 m tall; one guessed number would put the bend in the wrong place
  on all but one of them.

## Options rejected

**A trample texture.** A small viewport that records where the walker has been,
sampled and faded. It is what a persistent trail needs and it is what a larger
game would do. Rejected because the maintainer asked for a recovery rather than a
trail, and because it costs a viewport, a texture per map and a fade nobody has a
value for. The two-centre wake gives the same read for one extra uniform.

**Per-blade weights authored in the mesh.** Vertex colours or a second UV
carrying stiffness and phase. The right answer for authored grass. Rejected
because this grass is imported and carries neither, and hashing the world
position costs nothing and needs no pipeline.

**`world_vertex_coords` to avoid the matrix inverse.** It would remove one
`inverse(MODEL_MATRIX)` per vertex. Rejected because the model-space height and
the per-cell turn both need the model matrix anyway, and reconstructing them from
a world-space vertex is more arithmetic and more ways to be wrong than the
inverse costs — measured at 323,200 vertices for **5.9 ms a frame, with the
walker costing nothing measurable** on the machine this was written on.

## Consequences

**The cost is measured on one desktop GPU and says nothing about a phone.** The
project targets the Mobile renderer and this has never run on one. That is stated
rather than glossed: `tools/budget/` exists for exactly this kind of claim and it
does not cover shaders.

**The harness reads the quarantined library** (decision 0027) and runs on one
machine, on the same footing as the manifest builder. A clone can read what it
produced and cannot re-run it.

**The tuning constants are uniforms, not code.** Every number named in this entry
is exposed on the material, so the next pass is a slider rather than a commit.
