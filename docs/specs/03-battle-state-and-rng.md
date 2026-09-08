# 03 — Battle state model and RNG

**Status:** Draft
**Depends on:** `docs/architecture/layers.md`, specs 02, decisions 0001, 0009

Defines what a battle *is* at rest: the shape of the state, where each piece of
state lives, how it is addressed, and how randomness enters the core.

It deliberately says nothing about *when* things happen. Turn phases are spec 04,
effect resolution is spec 06, the event vocabulary is spec 07.

---

## 1. Shape

A battle is **two sides, each holding N slots**.

Two sides is not a simplification. Gen 4 has no free-for-all: a multi-battle with
four trainers is still two sides of two slots, and every side-scoped mechanic
(entry hazards, screens) is scoped to one of the two. Slot count is per-battle:
one for singles, two for doubles.

Doubles are in scope from day one (decision 0001), so:

- There is no `attacker` / `defender` shortcut anywhere in the model.
- Targeting is a first-class concept, never implied by position.
- A slot may be empty — after a faint, before its replacement arrives.

## 2. Addressing and identity

A **slot reference** is `(side_index, slot_index)`. It designates a position, not
a creature.

A **creature** has an identity stable for the whole battle, independent of which
slot it occupies or whether it is on the field at all. Slots hold a reference to
a party member; they do not own it.

The distinction matters because the two are targeted differently. A move targets
a *slot*. A burn belongs to a *creature* and follows it out of the battle.
Conflating them breaks the moment anything switches.

## 3. Where state lives

Four scopes. Each piece of state belongs to exactly one.

| Scope | Holds | Lifetime |
|-------|-------|----------|
| **Field** | Conditions affecting both sides | Until replaced or expired |
| **Side** | Conditions attached to one side, independent of who occupies its slots | Until expired; survives switching |
| **Slot** | Conditions attached to *occupying a position* | Cleared when the occupant leaves |
| **Creature** | Intrinsic and persistent state | Survives switching and the battle itself |

Creature scope covers HP, non-volatile status, PP, level, IVs, EVs, nature, held
item. Slot scope covers everything conventionally called *volatile*.

**This specification does not enumerate which effect goes where.** Each effect
declares its own scope, and that declaration is part of its definition
(spec 06). Enumerating them here would create a second source of truth that
drifts from the effect definitions — precisely the duplication the code standards
forbid.

The taxonomy also needs a per-effect *reset rule* rather than a blanket one: some
creature-scoped state is persistent yet resets on switch — a badly-poisoned
counter is the canonical example. Scope answers *where it lives*; the reset rule
answers *what clears it*. They are separate declarations.

## 4. Randomness: a semantic decision interface

The core never draws a random number. It asks for a **decision**, by name:

```
damage_roll()                             -> int    # index 0..15
accuracy_check(chance)                    -> bool   # percentage
critical_hit(numerator, denominator)      -> bool   # Gen 4 rates are fractions
secondary_triggers(chance)                -> bool   # percentage
speed_tie(first, second)                  -> SlotRef
multi_hit_count(minimum, maximum)         -> int
status_duration(minimum, maximum)         -> int
```

Probabilities arrive as explicit chances. The *rates* — what a critical stage is
worth, how long sleep lasts — are formulas derived from the oracle (spec 08) and
do not belong to the decider, which only answers whether a given chance came up.

The list above is illustrative, not closed by this document — but the *interface*
is closed at any point in time, and that is the property that matters:

> **Every random decision the engine makes is enumerable by reading one
> interface.**

Adding a source of randomness means adding a named method, which is a reviewable
event rather than a line buried in a formula. This is what makes the spec 02
decision policy substitutable wholesale, and what lets the fuzzer assert it has
covered every branch of chance.

Two implementations exist:

- **Seeded** — production and fuzzing. Constructed from a seed; identical seed
  and identical call sequence give identical results.
- **Scripted** — the differential harness of spec 02. Answers from a declared
  policy, consulting no randomness at all.

The core is indifferent to which it holds. It is injected at construction and
never reached for globally — the purity lint enforces the absence of `randi`,
`randf` and `RandomNumberGenerator` in the core.

### Determinism obligation

Determinism is a property of the *decider*, not of the core. The core must
therefore never make a decision depend on iteration order over an unordered
collection, on object identity, or on anything not reachable from the state and
the decider. Property-based tests assert this directly (spec 05).

## 5. Purity at the turn boundary

Turn resolution is `(state, commands, decider) -> (state', log)` and must not
touch its input state.

The state is **mutable during resolution** — that is idiomatic, fast, and readable
— but the turn takes a **deep copy on entry**. Externally the function is pure;
internally it is ordinary imperative code.

This is what makes a per-turn snapshot cheap, and per-turn snapshots are what make
replay and fuzzing shrinking possible.

Consequence: every state class carries an explicit `clone()`. State is held in
typed classes rather than nested dictionaries, because static typing is mandatory
and dictionaries would forfeit it. The verbosity is accepted.

## 6. Commands

A command is what a side submits for one slot in one turn: use a move (with an
explicit target), switch, use an item, forfeit.

Two constraints, both inherited from the PvP rules of decision 0001 and binding
even though PvP is deferred:

1. Commands are **serialisable structures**, never method calls.
2. Commands are collected for all slots on both sides **before** resolution
   begins. No code path may let one side observe another side's pending command.

The second is a property of this model, not of the turn machine: if commands were
readable as they arrived, no discipline in spec 04 could fix it.

## 7. Serialisation

The full battle state serialises to a plain data tree — no engine types, no
object references. Slot references serialise as index pairs; creature references
as party indices.

Required by save/load (spec 13), by PvP later, and by the differential harness,
which compares states as data.

---

## Open points

- The concrete list of decision methods closes with spec 06, once the effect
  system says which mechanics exist.

## Settled

- **Cloning versus serialisation.** Measured at 1.59× in favour of a
  hand-written `clone()`, which is what the engine uses. The drift the
  derivation would have prevented is pinned by a test instead. See
  decision 0019.
