# 0017 — Per-event visibility tags, with transformation rules

**Status:** Accepted
**Date:** 2026-09-07

## Context

Decision 0001 requires every log event to carry a visibility tag so each side can
be shown only what it is entitled to see. But hiding information is not simply
dropping events: an opponent does not see exact HP, they see a percentage.

## Decision

Every event is `public`, `private` to one side, or `transformed` — visible to
everyone in a reduced form, according to a transformation rule declared per event
kind.

This gives a filtered analogue of invariant 8:

> Replaying a viewer's filtered log reproduces the state observable by that
> viewer.

## Options rejected

- **Per-field visibility inside an event.** The finest possible grain and the
  most precise. But the declaration scatters across every field of every event
  kind, and nothing guarantees an event still makes sense once half its fields
  are stripped.
- **A separate log emitted per observer.** No filtering for consumers to
  implement. But the core would have to know its observers, it would repeat the
  same work N times, and the differential would no longer know which of the N
  logs to compare against the oracle.

## Consequences

Filtering becomes **testable** rather than a hand-checked list of what ought to
have been hidden — which matters because a leak in a PvP context is a cheating
vector, not a cosmetic bug.

Each new event kind must declare its transformation when it is `transformed`.
That is deliberate friction: it forces the question "what does the opponent
actually see?" to be answered when the event is designed, not when PvP ships.
