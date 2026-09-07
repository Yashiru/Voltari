# 0015 — Effects are built from three typed component types

**Status:** Accepted
**Date:** 2026-09-07

## Context

The effect system is the architectural risk of the project. Three mechanisms were
already decided separately — an ordered modifier pipeline, a distinct veto, and
an event queue for reentrancy — but how an effect is represented and bound to the
turn machine's anchors was left open.

Binding constraints: static typing mandatory, no metaprogramming, boring
idiomatic GDScript, and a turn machine that names no individual effect.

## Decision

An effect is an ID, parameters, a scope, a reset rule, a stacking rule, and a
list of components. Every component is one of exactly three types:

```
VltModifier   anchor, priority,  apply(ctx, value: int) -> int
VltVeto       anchor, priority,  blocks(ctx) -> bool
VltTrigger    anchor, priority,  run(ctx) -> void
```

Definitions are stateless and shared; instances hold the state and serialise.

## Options rejected

- **A base class with one virtual method per anchor.** The most conventional
  object-oriented shape, and the most immediately readable. But with roughly
  thirty anchors it becomes a god class of thirty empty methods inherited by
  every effect, and adding an anchor edits the file everything depends on. It
  also still needs each effect to declare which anchors it overrides, in order to
  index dispatch — arriving at this decision by a longer road.
- **A declared handler table of `(anchor, priority, kind, Callable)`.** The least
  ceremony, trivial indexing, and adding an anchor touches no existing effect.
  But `Callable` escapes static typing: a wrong signature becomes a runtime error
  instead of a compile-time refusal, contradicting the typing standard outright.

## Consequences

Three component types is the entire vocabulary. A behaviour that seems to need a
fourth kind indicates the anchor set is wrong, not that the vocabulary should
grow — this is the pressure valve that keeps the system from sprawling.

Components are reusable across effect kinds: *"+50% to Fire damage"* is written
once and used by an ability, an item and a field condition.

Because definitions are shared process-wide, a component that stores state in
itself is a defect rather than a style choice.

The cost is three concepts to learn instead of one, and slightly more indirection
between an effect and its behaviour than a virtual method would give.
