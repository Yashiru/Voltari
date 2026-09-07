# 02 — Fidelity contract

**Status:** Draft
**Depends on:** `docs/architecture/layers.md`, decisions 0001, 0002, 0003

This document defines what *correct* means for this engine. Every other
specification references it. When a behaviour is disputed, this is the document
that settles it.

---

## 1. What fidelity means here

The IP is original, so no recorded Gen 4 output exists for our species, moves or
abilities. Fidelity cannot be a property of *content* — only of *procedures*.

What we assert is that our procedures — damage, stat derivation, accuracy,
critical hits, speed ordering, effect resolution order — produce the same results
as the oracle when fed the same numeric inputs. The creature that carries those
numbers is irrelevant to the assertion.

## 2. The oracle

`@pkmn/sim`, gen4 mod, **pinned at 0.10.11**, exclusively. No other reference is
consulted to settle behaviour.

The fidelity target is properly named **"the gen4 mod of `@pkmn/sim`"**, never
"Gen 4". Showdown is a competitive simulator, not a cartridge emulator, and it
diverges from the original hardware in places. Those divergences are accepted
(decision 0002). Naming the target precisely is what keeps the differential
automatable: the question is never *"is this a Gen 4 bug?"* but only *"what does
the oracle do?"*.

## 3. Clean-room boundary

Showdown identifiers — species names, move names, ability names — appear in
**exactly one place**: `tools/oracle/`. That directory is development tooling. It
never ships, and the engine never reads it.

Generated fixtures contain only numbers and Voltari identifiers. A fixture that
names a Showdown entity is a defect in the generator.

Where a Voltari mechanic mirrors a Gen 4 one, the generator holds the mapping
(`voltari_ability_id -> showdown_ability_id`). That mapping table is the single
crossing point between the two vocabularies, and it lives on the tooling side of
the boundary.

## 4. Two vector families

Fidelity is asserted at two levels, because neither alone is sufficient.

### 4.1 Procedure vectors

Isolated computations with no turn context: damage, stat derivation from base
stats and IV/EV/nature, accuracy checks, critical rate, speed ordering.

Damage vectors record **all sixteen damage rolls**, not one. This tests the
formula exactly while coupling the assertion to no RNG at all.

```json
{
  "id": "damage/0001",
  "kind": "damage",
  "input": {
    "level": 50,
    "move": { "power": 80, "type": "fire", "category": "physical" },
    "attacker": { "attack": 200, "types": ["fire"] },
    "defender": { "defense": 150, "types": ["grass"] },
    "context": { "critical": false, "weather": null, "screens": [] }
  },
  "expected": { "rolls": [152, 154, 156, "…16 values"] }
}
```

### 4.2 Battle differential

Scripted battles replayed on both engines, compared event by event. This is
where resolution **order** is asserted — the actual risk of the project, and
something procedure vectors structurally cannot reach.

## 5. Forced decision protocol

Our engine uses its own RNG (decision from the initial draft), so seeds cannot be
shared with the oracle. Aligning two different call sequences bit-for-bit is not
achievable and is not attempted.

Instead, both engines are driven by the same **semantic decision policy**. Rather
than sharing random numbers, they share *answers*:

| Decision | Policy values |
|----------|---------------|
| Damage roll | fixed index 0–15, or `max` |
| Accuracy | `always-hit` \| `always-miss` |
| Critical hit | `never` \| `always` |
| Secondary effect | `always` \| `never` |
| Speed tie | explicit winning side |
| Multi-hit count | explicit integer |
| Status duration | explicit integer |

A battle fixture declares one policy for the whole battle, plus targeted
overrides where the mechanic under test *is* the random one (sleep duration,
multi-hit count).

On the oracle side this is implemented by substituting `@pkmn/sim`'s PRNG with
one that answers according to the policy. On our side, the injected RNG stream
(spec 03) is substituted for a scripted decider. Neither engine is modified for
testing; both already take their randomness as an injected dependency.

**Consequence:** most differential battles are built to be RNG-free by
construction — 100% accuracy moves, crits disabled, damage roll fixed. Damage
exactness stays the job of procedure vectors; the differential is there for
ordering and interaction.

## 6. Log normalisation

The two engines speak different vocabularies. The differential compares a
**normalised projection** of both, not raw logs.

- The projection is defined against our battle log vocabulary (spec 07).
- The mapping from Showdown protocol messages to that vocabulary lives in
  `tools/oracle/`, never in the engine.
- Events present in one vocabulary and absent from the other are listed in an
  explicit **ignore list**, each with a reason. That list is part of this
  contract: an event silently dropped is a hole in the differential.

## 7. Fixture format and location

```
tests/fixtures/oracle/
  procedure/    damage/, stats/, accuracy/, critical/, speed/
  battle/
tools/oracle/   generator, mapping tables, ignore list (Node, dev only)
```

Fixtures are JSON, committed, and readable without Godot or Node. The test suite
must stay hermetic: **running the tests requires neither network nor npm**.

## 8. Lifecycle

The oracle version is pinned and fixtures are **frozen**. Regeneration is a
deliberate act, never automatic:

1. Bump the pinned `@pkmn/sim` version.
2. Regenerate.
3. **Review the fixture diff.** A changed expected value means upstream changed a
   behaviour — that is a decision to take, not a result to absorb.
4. Commit generator change and fixture change together.

A regeneration that silently rewrites expectations defeats the purpose of having
them.

## 9. Outside the oracle's scope

`@pkmn/sim` simulates battles. It says nothing about:

- capture
- XP curves and level-up
- EV gain
- encounter tables
- evolution

These fall back on publicly documented formulas plus hand-derived vectors — a
**weaker test pillar**, accepted knowingly. Specs 10 and 11 state their own
reference source. No spec may claim oracle backing for a mechanic listed here.

## 10. Deviations

`docs/gen4-deviations.md` is created **empty**. The mechanism exists and is
tested from day one; there is no deviation list to start with.

A deviation entry declares: the behaviour, why we differ, and the test that
asserts *our* behaviour against the diverging oracle vector. Without that test,
the differential would be either permanently red or accidentally green.

## 11. Attribution

`@pkmn/sim` is MIT licensed. Anything derived from it keeps its attribution. No
third-party code enters the engine; the oracle is consulted at generation time
and never at runtime.

---

## Open points

- The set of mechanics covered by the first generation pass is not fixed here.
  It follows spec 06, since the effect system determines what is worth asserting.
- The ignore list of section 6 cannot be written before spec 07 defines the log
  vocabulary. It is created with the differential harness, not before.
