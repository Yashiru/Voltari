# 0022 — Effect state changes are one logged event, counted down by the engine

**Status:** Accepted
**Date:** 2026-09-08
**Amends:** spec 06 (§3), spec 07 (§3)

## Context

Counting a screen down mutated `remaining` and emitted nothing. `remaining` is
serialised, so replaying a battle produced a screen that had forgotten a turn
had passed — invariant 8, violated by every timed effect there could ever be.

Nothing caught it. The only replay test applied a burn, whose trigger emits
damage, so the state it changed travelled in the log by accident of what it did
rather than by design. The fuzzer registered burn and reflect and applied
neither, so no generated battle held an effect at all. The battle differential
compares against the oracle, which has no opinion about our replay.

It surfaced from an exhaustive mutation pass over `effect_dispatch.gd`, ordered
by decision 0021 — not from the defect itself, which had been latent since the
effect system landed.

## Decision

**One event kind, `effect_changed`**, carrying the resulting instance: applied,
refreshed, stacked, counted down, expired and removed all emit it.

**The engine counts durations down**, once, for every effect. An effect declares
how long it lasts and nothing more.

## Options rejected

**`effect_applied` / `effect_removed` as two kinds**, which is what spec 07's
illustrative vocabulary first listed. More explicit to read, but the countdown
has to re-emit "applied" every turn — two names for one mechanism, which the
one-concept-one-implementation rule exists to prevent. Whether a screen was set
up or ticked is a presentation question, answerable from the values.

**Deriving `remaining` from the turn it was applied on**, so no tick needs
logging and the whole class of desync becomes unrepresentable. Rejected because
Gen 4 has effects whose duration changes mid-flight — Light Clay extending a
screen, Trick Room re-set while running — and a derived duration cannot express
them. It would also have changed the state model in spec 03.

**Leaving the countdown to each effect**, as reflect did. It allows a
conditional or double-speed countdown, which nothing needs yet. Against it: the
engine already owned expiry, so the mechanism was split between two owners, and
nothing forces a new timed effect to declare a countdown — forgetting it yields
an effect that never ends and no test that says so.

## Consequences

`VltEffectDispatch.apply` and `remove` take a log. It may be null, because
building a battle that starts with a burn is not a battle event; during a turn
it must be given.

Collection, counting down and expiry now share one traversal. Three walks over
the same four scopes were three chances to disagree about what "on the field"
means.

Benched creatures are outside that traversal. Nothing can attach to one, so
nothing there can tick or expire, and every ticked effect is addressable by
(scope, position) — which is what the event needs to replay.

The fuzzer applies effects now. Removing the countdown event again makes seed 2
fail invariant 8 in two turns, so the guard is demonstrated rather than assumed.
