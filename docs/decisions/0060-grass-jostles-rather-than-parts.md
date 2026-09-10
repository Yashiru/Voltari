# 0060 — Grass jostles rather than parts

**Status:** Accepted
**Date:** 2026-09-10
**Supersedes in part:** decision 0059 — its harness and its method stand, its
deformation does not
**Recorded in:** spec 16, section 12

## Context

Decision 0059 built grass that opened around a walker: blades pushed radially
away, a wake behind, a spring back. It was checked against renders of one grass
tile and it looked right on that one.

On a map painted with the pack's dense tiles it did not. Blades splayed outward
around the character in a hard ring, and it read as **damage** rather than as
somebody passing through. The maintainer's word for what was wanted instead was
*gigoter* — to wiggle.

The mistake is worth naming precisely, because it was not a bug: every part of
that shader did what it was designed to do. **It was tuned against one asset and
generalised to a library.** The tile it was tuned on has sparse blades a third of
a metre apart; the one it failed on is a solid mass. A radial push is invisible
on the first and violent on the second.

## Decision

**A tuft never changes shape.** Every blade of a cell leans the same way by the
same amount, so the silhouette is the one the artist made. What changes is which
way it is leaning.

**Wind is small.** A slow gust travelling across the field, a swell so gusts
arrive and pass, and a shiver on each tuft at its own phase. The tip moves about
7% of the blade's length, against 34% before.

**Stepping into a cell rings that cell, once.** A damped swing lasting about
three quarters of a second, in a direction the cell picks from its own hash. Two
slots, because a cell is crossed in about half a second and one slot would cut
every swing off mid-air.

**How far a jostle reaches comes from the grid**, not from a number in a shader.
`GrassField` reads the map's cell width and sets the radius to a little over half
of it, so the cell stepped onto rings and the four beside it do not. A number in
the shader would ring five cells on a map painted at half the size.

## What is dropped, and what is kept

Dropped: the radial push, the splay along the heading, the two lagged centres and
the wake, the ring on release, the darkening under a foot, the walker's speed and
heading, and the per-cell size variation.

Kept: the length-preserving bend, the per-tuft phase and stiffness, the per-item
hinge and height written by the library builder, the root shading and tip tint,
and **the harness** — which is what caught this, in the end, by rendering a
second asset.

Per-cell rotation is kept and **defaulted off**. It is a real improvement to a
field of identical tiles and it changes a map that is already painted, which is a
decision for whoever painted it rather than a side effect of a shader.

## Options rejected

**Tuning the deformation down until it stopped looking wrong.** The obvious
answer, and it does not converge: the amount that reads on a sparse tile is the
amount that tears a dense one. The problem was the shape of the effect, not its
size.

**Per-asset tuning.** A different trample strength on each grass item, written by
the library builder alongside the hinge. It would work, and it makes every future
grass model a tuning session. Rejected for the same reason the hinge is measured
rather than authored: what can be derived should not be typed.

**A cell that flattens rather than swings.** Closer to what a footstep really
does. Rejected because the maintainer asked for the opposite in as many words,
and because flattening is deformation under another name.

## Consequences

**The effect no longer follows the character between cells.** Movement is
grid-locked (spec 14, section 2) and this now is too: the jostle fires on the
step, not on the drawing. A smooth walk crosses a cell in about half a second and
each cell rings as it is entered, which is the same rhythm the footfalls have.

**A step into a wall rings nothing.** Turning on the spot is not a footfall, and
grass that shook for it would make a wall feel like ground.

**One asset is no longer evidence.** The harness takes the item name as an
argument for exactly this reason now, and a claim about how the grass looks means
having rendered more than one of them.
