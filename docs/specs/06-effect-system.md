# 06 — Effect system

**Status:** Draft
**Depends on:** specs 03, 04, 05; decisions 0001, 0010, 0011, 0012

The architectural risk of the project. Not the damage formula — the interaction
engine: moves, abilities, items, statuses, stat stages, weather, hazards,
multi-turn moves, priority, protect, substitute, switch-in triggers, and above
all the ordering rules between all of it.

The pattern is laid down once here and every piece of content is then built on
it. It is never improvised in flight.

---

## 1. Three component types, and only three

An effect owns a list of components. Every component is one of exactly three
types, mirroring the three mechanisms that were decided separately:

```
VltModifier   stage,  priority,  contribute(ctx, modifiers) -> void
VltVeto       anchor, priority,  blocks(ctx) -> bool
VltTrigger    anchor, priority,  run(ctx) -> void
```

A modifier **contributes a ratio** rather than returning a value. Several
modifiers on one stage therefore compose *before* the stage runs; applying them
one after another would round at each application and change the result, and
per-step rounding is the specification (spec 08).

Modifiers attach to **formula stages**, vetoes and triggers to **turn anchors**.
That split is not a compromise: a turn phase has no value to modify, and a
formula stage is not a moment at which something can be blocked. It also avoids
one enumeration having to span both spaces.

Three types is the whole vocabulary. A component that needs a fourth kind of
behaviour is a signal that the anchor set is wrong, not that the vocabulary
should grow.

Each signature is precisely typed, there is no base class carrying a method per
anchor, and dispatch indexes directly by anchor. A component such as *"+50% to
Fire damage"* is written once and reused by an ability, an item and a field
condition.

## 2. Definition and instance

Two distinct things, conflated at everyone's peril:

- **`VltEffectDefinition`** — static, shared, **stateless**. Declares the ID,
  parameters, scope, reset rule, stacking rule and components.
- **`VltEffectInstance`** — one per application. Holds the state: which
  definition, the source that applied it, remaining duration, counters. Fully
  serialisable, and lives in the scope the definition declares (spec 03).

Components hang off the definition and are therefore stateless. They read and
write instance state through the context. A component that stores anything in
itself is a defect: definitions are shared across every battle in the process.

## 3. Declaring an effect

| Field | Meaning |
|-------|---------|
| `id` | Stable, `snake_case`, never reused once published |
| `scope` | field, side, slot or creature (spec 03) |
| `reset_rule` | What clears it — separate from scope, and deliberately so |
| `stacking_rule` | `unique`, `refresh` or `stacking` |
| `parameters` | Numbers and identifiers from content data |
| `components` | The modifiers, vetoes and triggers |

`stacking_rule` answers what happens when an effect is applied to a scope that
already carries it: refuse it, reset its duration, or add a layer. It is a
per-effect declaration because there is no correct global default — a burn
refuses, a screen refreshes, hazard layers stack.

## 4. Anchors and ordering

An **anchor** is a named point where the engine consults effects. The anchor
enumeration is the contract between the turn machine (spec 04) and this system,
and it is the *only* coupling between them: the turn machine names no effect, and
effects name no phase of the turn machine other than through an anchor.

Anchors come from two sources: the phases of spec 04, and the stages of the
formulas of spec 08.

At a given anchor, components run ordered by:

1. declared **priority**
2. then **speed order** of the owning slot
3. then a deterministic tiebreak on side index, then slot index

The third rule exists solely so that ordering never depends on iteration order
over an unordered collection — the obligation from specs 03 and 04. It is never
reached in practice, and it is what makes invariant 6 hold.

## 5. The modifier pipeline

Fidelity at the point requires that modifiers apply in a fixed order **with
integer rounding at each step**. A bag of unordered hooks cannot be faithful.

The rule that keeps this honest:

> **The formula defines the stages. Modifiers attach to stages. The pipeline
> never invents an ordering.**

Each stage of a formula is an anchor. A modifier declares which stage it attaches
to and does its own integer arithmetic — `value * 3 / 2` rather than a float
multiplier — so per-step rounding is preserved rather than approximated. Priority
orders modifiers *within* a stage; it never moves one across stages.

Spec 08 owns the stage list. This document owns only the guarantee that stages
are respected.

## 6. Veto

A veto is not a modifier that returns zero. It blocks upstream, and blocking is
observably different: no damage is computed, no secondary effect rolls, the log
records a block rather than a zero.

Vetoes evaluate before the work they guard. The first veto that blocks stops
evaluation — remaining vetoes at that anchor are not consulted, since the
question is already answered.

## 7. Triggers, the event queue, and reentrancy

Triggers never call each other. A trigger **enqueues** events; the queue is
drained at defined points.

Cascades are the reason: a hit that causes a faint, that fires an ability, that
causes another faint. Direct invocation would make that a recursion whose depth
and ordering nobody controls.

- The queue is drained after the current anchor completes, before the turn
  machine advances.
- Draining is **depth-limited**. Reaching the limit is a defect, not a condition
  to recover from: it fails loudly, which is what makes invariant 4 provable
  instead of hoped for.
- Exact cascade ordering is a fidelity question and is settled by the oracle
  (spec 02), not by preference.

Applying and removing effects happens here too: a trigger calls
`ctx.apply_effect(...)`, which consults the stacking rule of section 3.

## 8. Where data stops and code starts

> You do not put logic in data. You put anchor points in the engine and write the
> logic in ordinary GDScript at those points.

Content data holds **parameters**: power, type, accuracy, chance, duration,
which effect IDs to apply. Code holds **behaviour**: the component classes.

The line that must not be crossed:

**No conditional logic in YAML.** A move whose power doubles against a sleeping
target is a component class, not a data expression. The moment the content format
grows an `if`, it has become a DSL — which is metaprogramming, which is
forbidden, and which would mean reinventing piece by piece the expressive power
GDScript already gives for free.

## 9. Registry and dispatch

The registry maps effect ID to definition. It is built once from the content
payload injected into the core; the core reads no file (spec 03).

Dispatch at an anchor: collect the active instances in the relevant scopes,
gather their components for that anchor, sort by section 4, apply. The registry
precomputes which definitions carry components at which anchor, so inactive
effects cost nothing.

## 10. Testing obligations

Beyond the three pillars of spec 05, two **meta-tests** guard the system itself:

1. Every registered effect ID appears in at least one test. An effect with no
   test is unverified content masquerading as a feature.
2. Every anchor in the enumeration is exercised by at least one test. A dead
   anchor is either untested or unused, and both need to be visible.

Interaction tests are the point of this module: a move with a secondary effect,
plus an ability, plus weather, plus an item, plus a status, and every ordering
question between them. Single-effect unit tests are necessary and nowhere near
sufficient.

---

## Open points

- Modifier spaces beyond damage — speed, accuracy — get their own stage
  enumerations when those formulas are staged. Only the damage pipeline is
  staged today.
- The event queue's depth limit needs a number, chosen once real cascades exist.
- Whether component instances may be shared between definitions, or must be
  constructed per definition, is decided when the first shared component appears.
