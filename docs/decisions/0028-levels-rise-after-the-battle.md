# 0028 — Levels rise after the battle, not during it

**Status:** Accepted
**Date:** 2026-09-08
**Recorded in:** spec 10, sections 5 and 6

## Context

Gen 4 awards experience the moment an opponent faints, and applies the level-up
immediately. Stats change mid-battle; a creature can win a fight it would
otherwise have lost.

Reproducing that means progression running inside the turn.

## Decision

Experience, levels, moves and evolutions are applied by a **post-battle
pipeline**. A creature that would have levelled mid-battle benefits once the
battle is over.

## Options rejected

**Matching the cartridge**, applying the level-up at the faint. It is what the
game does, and the divergence is observable in play — a close fight can end
differently.

Rejected for what it costs the frontier. The core would emit events for changes
L1 causes, progression would enter the resolution order, and the turn machine
would gain a reason to know what experience is. Specs 04 and 06 are shaped
around the core naming no effect and branching on none; this would be the first
exception, in the layer with the strongest purity claim.

The divergence is also bounded: it only shows in a battle where a level-up would
have changed the outcome, and only for the remainder of that battle.

## Why this is not a deviation entry

`docs/gen4-deviations.md` records divergences from the **oracle**, and each entry
owes a test asserting our behaviour against the diverging oracle vector.

The oracle covers battle mechanics only (spec 02, section 3). It has no
experience and no levels, so there is no vector here to diverge from and no test
of that shape to write. Filing it there would put an entry in a register that
cannot hold it, and would quietly widen what that file claims to cover.

This is a divergence from the **cartridge**, in an area the oracle never
reached. It is recorded here.

## Consequences

The core stays ignorant of experience, which is what keeps the L0/L1 boundary a
boundary rather than a convention.

Nothing automatic will catch a regression here — the differential cannot see it.
The guard is spec 10 section 9: published formulas, hand-derived vectors, and
property tests, which is a weaker pillar than the differential and is knowingly
accepted.
