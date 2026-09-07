# 0001 — Layered architecture with a pure simulation core

**Status:** Accepted
**Date:** 2026-09-07

## Context

The project requires 100% test confidence on the effect system, fuzzing over
random move sequences, and complete determinism at a fixed seed. The initial
breakdown listed modules as a flat list, mixing pure battle logic with the
rendering pipeline.

## Decision

The engine is organised in layers where a layer may only depend on layers below
it. The simulation core (L0) is pure computation: it may use the GDScript
language but not the Godot engine. Forbidden inside the core: `Node`, scene tree,
`Resource`, `await`, `signal`, global RNG, clocks, file I/O. Data arrives already
parsed and typed, injected by an external loader.

Three consequences are part of the decision:

- The core emits a serialisable event stream (the battle log) rather than
  driving presentation directly.
- The core emits identifiers, never localised text.
- Battle state is sides x slots from day one, never attacker/defender.

## Options rejected

- **Battle logic living in Godot nodes with animation in the loop.** Simpler to
  wire to the UI, but it makes determinism, fuzzing and mutation testing
  unreachable — all three require replayable pure computation.
- **A flat module list.** Mixes abstraction levels and gives no rule for what may
  depend on what.

## Consequences

Fuzzing, differential testing and mutation testing become natural on seeded pure
computation. The UI has to be written against the log rather than against engine
internals. The purity rule is enforced by a CI lint (see 0008), not by review.
