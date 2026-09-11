# 0046 — Creature runtime code leaves the species quarantine

**Status:** Accepted
**Date:** 2026-09-09
**Refines:** decision 0027 (species containment)
**Recorded in:** spec 16, section 6

## Context

Decision 0027 keeps `game/assets/species/` out of the index, out of the
history, and out of every export preset. It was written for third-party models:
not ours, not licensed to us, and useful only until the artist's arrive.

The runtime script that makes a creature work, and the shaders it assigns, were
installed into `game/assets/species/_shared/` — inside that quarantine.

They are not third-party. They are the project's own code, contained by
proximity rather than by nature.

## The consequence nobody chose

An exported build has no script to display a creature with. The guard removes
the directory from every export preset by design, and the design assumed the
directory held only assets.

This was not going to surface until the first export, and it would have surfaced
as creatures that do not appear.

## Decision

**The runtime script and the shaders move into the engine**, outside the guarded
directory. What stays behind the guard is what the guard was written for: the
models, their textures and their scenes.

The pipeline's install destination changes accordingly.

## Options rejected

**Moving it when the fakemon arrive.** Nothing to do today. Rejected because it
leaves spec 16 describing a location that does not exist, and leaves every
exported build broken in the meantime — a state that is easy to forget precisely
because nothing exercises it yet.

**Two copies, one each side.** Nothing breaks immediately. Rejected outright: the
same mechanism in two files is what the code standards call a defect, and this
particular mechanism is the one every creature in the game depends on.

## Consequences

**The guard gets narrower and no weaker.** It still refuses the index, the
working tree, the whole history and any export preset that does not exclude the
directory. It simply now guards only what is actually not ours.

**A species and a fakemon differ in exactly one way: provenance.** Same scene
shape, same script, same manifest. That is what makes replacing the roster a
content change rather than a port — and it is only true because the shared half
lives outside the quarantine.
