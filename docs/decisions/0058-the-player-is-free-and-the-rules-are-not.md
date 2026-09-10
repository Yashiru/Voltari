# 0058 — The player is free and the rules are not

**Status:** Accepted
**Date:** 2026-09-10
**Supersedes:** decision 0051 (the stick is quantised before the world) and
decision 0056 (a diagonal is a staircase)
**Recorded in:** spec 14, section 2

## Context

Movement was locked to the grid. Spec 14 argued for that at length, and one of
its arguments was an argument against ever changing it:

> Under free movement it would become a distance threshold — a constant with no
> defensible value, tuned until it felt right and then never touched again.

The maintainer asked for free, omnidirectional movement with the grid kept, and
named the rule themselves: **the character's origin decides which cell they are
in.**

## Decision

**Position is continuous, in metres. Every rule still reads a cell.**

The trigger that replaced "a step" is **the occupied cell changing**. Warps,
events and encounters keep the rule and the order they always had, fired by
crossing a boundary instead of by a discrete step.

**The old argument does not survive contact with the current grid.** There is no
distance threshold, because there is no distance: a cell boundary is a boundary
whatever route was taken to it. No constant was added. The encounter rate keeps
its meaning exactly — it is still per cell entered.

**What stops you is still the painted blocking layer.** A radius, and the cells
under the four corners of the box around it. Each axis is tried separately, so
walking into a wall at an angle slides along it — which falls out of the order
rather than being written. No physics body and no collision shapes (spec 14,
section 1 survives intact).

**The origin decides which cell; the radius decides where you may be.** Those are
two questions and giving them one answer is what makes a character either clip
through corners or refuse to enter a corridor.

## Options rejected

**Godot physics.** A `CharacterBody3D` and shapes generated from the blocking
layer. Rejected because it contradicts spec 14 section 1, puts collision shapes
back into a tile library that deliberately has none, and makes "what stops you"
two things instead of one.

**Nothing stops you.** The blocking layer serving rules only. Rejected by the
maintainer; it would also make the layer's name a lie.

**A distance travelled, rather than a cell entered.** What spec 14 predicted. It
needs a distance to compare against, and the only defensible one is the cell
width — at which point it is the same rule with an extra step and a rounding
error.

## What it costs

**Decisions 0051 and 0056 are superseded, and most of `VltStepIntent` is gone.**
The dominant axis, the bias near 45 degrees, the flick that turned without
walking, and the staircase two keys traced: free movement answers all four by not
asking the question. Two days of recent work retired, which is the right outcome
and not a regrettable one — the staircase existed to imitate a diagonal, and now
there is a diagonal.

**`VltGridWalker` is gone and `VltFreeWalker` replaced it.** Keeping both would
have been two ways to move, which this repository does not do.

**Interpolation is gone too.** `CellGlide` existed to draw a body catching up
with a cell it had already reached. There is nothing to catch up with now.

**A save still stores a cell.** Loading stands you in the middle of the one you
left. Storing metres would put a float in a document that has to be read for
years to buy half a metre.

**The corners are square.** A disc sampled at the corners of its bounding box is
slightly larger than a disc, so a character rounds an inside corner a few
centimetres wider than they need to. Measured, accepted, and cheaper than the
alternative — which is a real distance-to-cell test, and a formula the overworld
was built to avoid carrying.
