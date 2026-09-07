# 0012 — Turn resolution suspends, with the continuation held in the state

**Status:** Accepted
**Date:** 2026-09-07

## Context

Decision 0001 makes turn resolution a pure function of state, commands and
randomness. But a turn cannot always run to completion: when a creature faints, a
replacement must be chosen, and that choice depends on what just happened in the
turn. Not all input exists when resolution starts.

## Decision

`resolve` returns either `Complete(state', log)` or
`NeedsInput(state', log, request)`. The caller supplies the requested commands
and calls `resolve` again.

The position within the turn is **part of the battle state**, which stays
serialisable at every suspension point. The request kind is named, so further
kinds can be added without changing the API shape.

## Options rejected

- **A stateful battle object with `step()`.** Considerably simpler to write, but
  mid-turn state stops being serialisable: no saving mid-battle, no PvP
  reconnection, and replay degrades to partial.
- **Replacement policy declared up front.** Keeps resolution a single pure block,
  but corresponds to no real game, and takes the most tactical decision in a
  battle away from both the player and the AI.

## Consequences

Saving mid-turn, PvP request/response and total replay all fall out of the same
mechanism rather than being three separate features.

The cost is a resolution loop the caller must drive, rather than a single call —
and a battle state that must encode where it is inside a turn, which every state
migration will have to carry.
