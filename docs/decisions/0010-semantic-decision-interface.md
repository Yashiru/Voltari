# 0010 — Randomness is a semantic decision interface

**Status:** Accepted
**Date:** 2026-09-07

## Context

Decision 0009 requires randomness to be injectable as a decider, so the
differential harness can substitute a scripted policy wholesale. That leaves the
shape of the interface open.

## Decision

The core never draws a random number. It asks for a **named decision**:
`damage_roll()`, `accuracy_check(chance)`, `critical_hit(stage)`,
`secondary_triggers(chance)`, `speed_tie(a, b)`, `multi_hit_count()`,
`status_duration(kind)`.

Two implementations: seeded, for production and fuzzing; scripted, for the
differential.

## Options rejected

- **Generic RNG with named streams** (`rng.stream("damage").range(85, 100)`). A
  narrow interface that never changes, but the scripted policy would have to
  intercept by stream name, and nothing stops two mechanics sharing a stream by
  accident — which makes forcing a specific decision imprecise.
- **Streams underneath, semantic façade on top.** Both benefits, but two layers
  implementing one mechanism, which the code standards forbid outright.

## Consequences

Every random decision the engine makes is **enumerable by reading one
interface**. Adding a source of randomness becomes a reviewable event rather than
a line buried inside a formula, and the fuzzer can assert it has covered every
branch of chance.

The cost is a widening interface: each new random mechanic adds a method. That is
accepted — the widening is exactly the signal we want to see in review.

Determinism becomes a property of the decider rather than of the core. The core
must therefore never let a decision depend on iteration order over an unordered
collection, on object identity, or on anything unreachable from the state and the
decider.
