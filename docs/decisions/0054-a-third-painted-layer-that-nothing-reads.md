# 0054 — A third painted layer that nothing reads

**Status:** Accepted
**Date:** 2026-09-10
**Refines:** decision 0038 (the overworld is engine-native)
**Recorded in:** spec 14, section 3

## Context

Maps carried two painted layers: what exists, and what stops you. That was enough
while the tile library was two grey boxes.

It stops being enough as soon as there is a library worth painting with. Ninety
models arrived, and most of what makes a map look like a place — a flower, a
crack in the ground, a border along a path — is neither of the two things the
existing layers can say. A flower does not make a cell exist and does not stop
anybody.

## Decision

**A third `GridMap` on the map, and no accessor for it.**

`VltWorldMap.decor` is exported so it can be painted and so it saves with the
scene. Nothing on the class reads it: there is no `decor_at`, no
`has_decoration`, nothing. The rules cannot see it because there is no way to ask.

Nothing validates it either.

## Options rejected

**Baking decoration into terrain tiles.** No new layer, no spec change, and the
existing two layers keep meaning exactly what they meant. Rejected on
combinatorics: the tile library would need one item per pairing of ground and
ornament, and adding a ground type would mean re-authoring every ornament that
can sit on it. That is the cost paid every time, to avoid a cost paid once.

**Decoration as nodes rather than a painted layer.** It is what warps and zones
already are, so the mechanism exists. Rejected because decoration is dense —
hundreds of items on a map — and nodes are the expensive way to say something a
grid says for free. Nodes are for things that carry configuration; a flower
carries none.

**A layer with an accessor, "in case something needs it later".** Rejected as the
specific way this decision goes wrong. The moment a rule *can* read decoration,
some rule eventually does, and then a change of art becomes a change of
behaviour — which is exactly what decision 0038's split between painted layers
was for.

**Validating it.** Decoration off the edge of the map is a real mistake and a
visible one. Spec 14 section 7's criterion is that what gets checked mechanically
is what review cannot catch by eye, and this is the opposite case.

## Consequences

**Three layers to paint, and a map that is wrong in a new way only visually.** No
test will ever fail because of decoration, by construction.

**The tile library can be split by intent** — ground, obstacles, ornaments — but
nothing enforces that split. Painting a wall mesh into the decoration layer
produces a wall you walk through, and that is not detectable: spec 14 section 3
already accepts the same hazard between terrain and blocking, and this widens it
by one layer rather than introducing it.

**Existing maps are unaffected.** The field is optional and absent maps read as
having no decoration.
