# 0016 — The log is emitted in resolution order

**Status:** Accepted
**Date:** 2026-09-07

## Context

The engine computes and then applies; the games display "It's super effective!"
*before* draining the health bar. If the log is ordered by computation, the UI
has to reorder it to reproduce the original pacing.

Perceived pacing is what makes a battle feel right, so where that ordering lives
is a structural question, not a detail.

## Decision

The core emits **in resolution order** and holds no knowledge of presentation.

In Gen 4 the two orders coincide: the game resolves and presents in lockstep.
Where they appear to diverge, the correction is to change the resolution order —
never to add presentation hints to the core.

## Options rejected

- **Computation order, reordered at presentation.** Leaves the core free to
  organise itself however it likes. But the game's pacing becomes a second source
  of truth, maintained far from the engine, and the differential no longer covers
  it.
- **Resolution order plus grouping markers.** More expressive for animation. But
  those are presentation hints inside the core, and they have no counterpart in
  the oracle's log, so they escape the differential entirely.

## Consequences

Pacing is covered by the differential rather than by review: the oracle's log is
itself in resolution order, so a mismatch fails a test instead of being noticed
by eye months later.

The purity rule is preserved — the core stays ignorant of the UI.

The cost is that a pacing problem must be fixed in the resolution order itself,
which is a deeper change than reordering a list in the UI would have been. That
is the intended trade: it keeps one source of truth.
