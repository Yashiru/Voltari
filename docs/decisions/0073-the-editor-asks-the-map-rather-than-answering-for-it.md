# 0073 — The editor asks the map rather than answering for it

**Status:** Accepted
**Date:** 2026-09-12
**Recorded in:** spec 14, section 1

## Context

The map editor is about to grow an overlay that draws what stops you: the
footprint polygons, the cells blocked whole, the edge of the map. The point of
drawing them is to be able to trust what you see, which means the overlay has to
draw **the shapes the game uses** and not shapes that merely resemble them.

Those shapes live in `VltWorldMap.footprints()` and `VltFootprint.on()`, in
`addons/voltari/`. Nothing in that directory is `@tool`, and that was not an
oversight — the boundary held at a hundred per cent across the whole engine
addon. `map_placement.gd` states the reasoning it was built on: an editor holds a
non-`@tool` script as a placeholder instance and refuses to call methods on one,
so the editor reads `GridMap` properties and redoes the cell arithmetic itself,
which is "cheaper than making the engine run in the editor".

That reasoning was correct for what it covered. What it covered was three
property reads and a rounding rule.

## Decision

**`VltWorldMap` and `VltFootprint` are `@tool`.** The editor asks them the same
questions a test asks, and gets the same answers.

Nothing else in `addons/voltari/` changes. The boundary is not abolished, it is
crossed at two named places, for one stated reason: these two classes are what
answer "what stops you", and that question now has a second legitimate asker.

Both are safe to run in an editor by construction. Neither has a `_ready`, a
`_process`, or an `_init` that does anything; `VltFootprint` is pure static
geometry over a mesh, and `VltWorldMap` is exported data plus queries over it.
The one piece of state is the lazily built shape cache, and the method that
clears it was already written for this caller — its comment names the editor
first.

## Options rejected

**Re-deriving the shapes in editor code.** The boundary stays absolute and the
overlay walks the `GridMap` properties itself. Rejected, and not narrowly: it
would be a second implementation of the derivation that decision 0072 had just
finished making the only one. Two implementations drift, and the first symptom
of the drift is an overlay that draws a hitbox the game does not use — which is
the worst possible defect in a tool whose entire job is to be believed.

**Extracting the reading into a shared `@tool` helper**, used by `VltWorldMap`
at runtime and by the editor. It also yields one implementation, and it keeps
the engine node itself non-`@tool`. Rejected as more machinery than the problem
has: it adds a class, turns part of `VltWorldMap` into a relay, and buys a purity
that is not load-bearing here. The core's purity is enforced by a lint and is
what makes fuzzing and mutation testing possible (spec 05); the world's distance
from the editor was never that, because `world/` depends on Godot on purpose
(decision 0038) and is exempt from the lint for exactly that reason.

**Marking the whole addon `@tool`.** Rejected: the two classes above have a
reason, and the rest do not. A blanket annotation would make "does this run in
the editor" unanswerable without reading every file.

## Consequences

A crash inside `VltWorldMap` or `VltFootprint` can now take the editor down
rather than only the game. That is the real cost and it is accepted: both are
already under test, and an author painting a map is better served by a tool that
tells the truth and can break than by one that cannot break and quietly lies.

The purity lint is untouched — it covers `core/`, `deciders/`, `rules/` and
`save/`, and `world/` was never in its scope (spec 01).

The next class somebody wants to reach from the editor does not inherit this.
The reason above is specific to shapes; anything else gets its own argument.
