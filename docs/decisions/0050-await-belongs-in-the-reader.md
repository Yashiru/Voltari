# 0050 — `await` belongs in the log reader, and only there

**Status:** Accepted
**Date:** 2026-09-09
**Refines:** decisions 0012 and 0044 (suspendable turn resolution, atomic events)
**Recorded in:** spec 17, section 2

## Context

The repository has two machines that advance until they need an answer and are
then resumed: turn resolution and the event run. Neither uses `await`, and the
core forbids it outright.

The battle log reader is a third thing that has to stop and continue — after each
event, until its animation finishes.

## Decision

**The reader is a queue drained with `await`.** Take an event, play it, wait,
take the next.

## Why the rule does not reach here

The other two suspend for reasons the reader does not share:

| | Turn / event run | Log reader |
|---|---|---|
| Held across a save? | Yes, or must provably not be | Never |
| Testable without a frame? | Required | Meaningless — it *is* elapsed time |
| Deterministic replay? | The whole point | Nothing to replay |

A reader persists nothing and exists precisely *because* time passes. Suspending
it by hand would buy none of the three properties and cost a driver loop that
does nothing but call back.

The core's ban stands untouched: it is about the core, and the reader is L4.

## Options rejected

**Suspending it like the other two.** One shape across the whole repository, and
testable without a scene tree — genuinely attractive, and the reason this is a
recorded decision rather than an obvious call.

Rejected because the consistency would be with the *mechanism* rather than with
the *reason*, and the reason is what the other two decisions are actually about.
Copying a shape whose justification does not apply is how a codebase acquires
ceremony.

**A timeline built up front**, every animation dated before anything plays.
Rewinding and speeding up become trivial. Rejected because it requires knowing
how long everything takes before starting, and an animation whose length depends
on the model does not offer that.

## Consequences

**The reader is where the game's pace lives**, and the only place with an opinion
about how long anything takes. Pacing can be tuned without touching a rule.

**Three machines, two shapes, and a written reason for the difference.** The risk
this decision carries is somebody later "unifying" them; the table above exists
so that whoever does can see what they would be giving up.
