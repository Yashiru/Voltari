# 0067 — The turf watches the map, and waits for it to settle

**Status:** Accepted
**Date:** 2026-09-11
**Builds on:** decision 0066 — the boundary this keeps up to date
**Recorded in:** spec 16, section 12

## Context

A patch of turf is worked out once, from the map as it stood when it was sown.
Paint a well in the middle of a lawn afterwards and the grass keeps growing
through it, because nothing tells the patch that anything happened.

`VltFoliagePatch` has the same behaviour for the same reason, so there was no
precedent to follow and this is a new mechanism rather than a bug fix.

## What made this a choice rather than an obvious yes

A rebuild is not cheap. Measured on the maintainer's own map, growing a 625-cell
patch again takes **252 ms** — it walks every obstacle on every layer, slices each
model at the height a blade occupies, stamps the results into a grid and runs a
distance transform over it. Doing that on every change would mean doing it once
per cell under a dragged brush, and painting would stop being possible.

So the question was never "should it notice" but "how much may it cost", and the
answer decides the shape:

- On every change — unusable.
- Never, and a button to ask for it — free, and something to remember.
- On the change, deferred until the changes stop — one rebuild per stroke.

## Decision

**The editor plugin looks four times a second, and regrows a patch on the first
look that finds the map unchanged.**

The look is a signature: `TurfPatch.map_signature()` folds, into one integer,
exactly what `_footprints` reads — which cells each layer holds, which item is in
each, which way each is turned, and where the prop nodes beside the grid stand.
Measured at **152 µs** on that same map, which is what makes looking four times a
second rather than reacting to a signal affordable.

It has to include the **orientation**, and that is the part a cell list would
miss: a fence turned where it stands adds no cell and removes none, and its
footprint turns with it.

The interval and the settling time are one number on purpose. A patch is regrown
on the first look that finds nothing new, so a brush dragged across ten cells
costs one rebuild after the last of them rather than ten.

### Where each half lives

The signature is the **patch's**, because only the patch knows what it was grown
from, and keeping the two in one file is what stops them drifting apart — a
signature that failed to include something `_footprints` reads is a lawn that
silently stops updating.

The loop is the **plugin's**. It is editor tooling, it already walks the edited
scene every frame for placed nodes, and a running game never repaints a `GridMap`
— so nothing watches at runtime and this costs the game nothing.

### And a switch

`follow_map`, per patch, on by default. A patch large enough for a quarter-second
hitch to be felt can turn it off and be resown by hand.

**A second way to do one thing, accepted knowingly.** The rule against that exists
so a codebase does not grow two implementations of one idea; here there is one
implementation and one switch on it, and the cost it guards against is measured
rather than imagined.

## Rejected

**A signal from `GridMap`.** There is none. A `GridMap` is a node, not a resource,
and it emits nothing when a cell is painted. Polling is not a shortcut here, it is
the only door.

**Watching from the patch itself**, in `_process` under `Engine.is_editor_hint()`.
It would work without the plugin, and it puts an editor-only loop on every
instance of a presentation node — one per patch rather than one per scene, in a
file that decision 0046 keeps free of the editor.

**Doing the same for foliage** in the same change. It has the same gap and a much
heavier rebuild — it bakes a mesh — so it deserves its own measurement rather than
this one's answer. The mechanism is written and will fit it unchanged.
