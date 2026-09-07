# 0011 — Mutable battle state, deep-copied at the turn boundary

**Status:** Accepted
**Date:** 2026-09-07

## Context

Decision 0001 makes turn resolution a pure function
`(state, commands, decider) -> (state', log)`. How that guarantee is held
internally was left open.

## Decision

The state is mutated freely during resolution, but the turn takes a **deep copy
on entry**. Externally the function is pure and the caller's state is never
touched; internally the code is ordinary imperative GDScript.

Every state class carries an explicit `clone()`. State lives in typed classes
rather than nested dictionaries, since static typing is mandatory.

## Options rejected

- **Strict immutability**, each mutation producing a new state. Excellent for
  step-by-step debugging and time travel, but GDScript has no structural sharing:
  every event would copy the whole state. It is also far from the idiomatic,
  boring style the standards require.
- **Mutation with no copy.** Fastest and simplest to write, but purity would hold
  by convention only — a caller reusing its input state afterwards would silently
  get a wrong result, and replay would be impossible.

## Consequences

Per-turn snapshots are cheap, which is what makes replay and fuzz-case shrinking
practical.

The verbosity of hand-written `clone()` on every state class is accepted.

This leaves one question open, recorded in spec 03: `clone()` and serialisation
are two mechanisms doing the same job. Deriving one from the other would satisfy
"one concept, one implementation" and guarantee they never drift, at a
measurable per-turn cost. It needs measurement before being settled — mutation
testing requires a fast suite.
