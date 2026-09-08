# Specification plan

Ordered list of the specification documents to write. Architecture is settled
before implementation; no gameplay code lands ahead of a validated spec.

See `docs/architecture/layers.md` for the layered decomposition these specs
describe.

---

## Block 0 — Foundations

| #  | Document | Scope |
|----|----------|-------|
| 01 | [Conventions and repository structure](01-conventions.md) — *draft* | Naming, engine/game separation, language, decision journal, `.gitignore`, CI |
| 02 | [Fidelity contract](02-fidelity-contract.md) — *draft* | Scope, oracle, vector generation, `gen4-deviations.md` |
| 03 | [Battle state model and RNG](03-battle-state-and-rng.md) — *draft* | Sides x slots, targeting, state scopes, decision interface, serialisation |
| 04 | [Turn state machine](04-turn-state-machine.md) — *draft* | Phases, command collection, speed ordering, anchor points for effects |
| 05 | [Core test strategy](05-core-test-strategy.md) — *draft* | Differential vectors, property-based tests, fuzzing, mutation testing, coverage floor |

## Block 1 — The hard part

| #  | Document |
|----|----------|
| 06 | [Effect system](06-effect-system.md) — *draft* |
| 07 | [Battle log](07-battle-log.md) — *draft* |
| 08 | [Formulas](08-formulas.md) — *draft* |

## Block 2 — Data and rules

| #  | Document |
|----|----------|
| 09 | [Data schema and content build](09-data-schema.md) — *draft* |
| 10 | [Progression and post-battle pipeline](10-progression.md) — *draft* |
| 11 | Capture |
| 12 | Battle AI |

## Block 3 — Game and presentation

| #  | Document |
|----|----------|
| 13 | Save / load and migration |
| 14 | Overworld and encounters |
| 15 | Event scripting |
| 16 | Creature and character rendering — rigs, animation, asset pipeline, mobile budget |
| 17 | UI and battle log consumption |
| 18 | Input and platforms |

## Deferred

| #  | Document |
|----|----------|
| 19 | Networking / PvP — deferred, but its constraints are binding from block 0 |

---

## Ordering rationale

**The fidelity contract is 02, not later.** It defines what "correct" means, and
every subsequent spec references it.

**The test strategy (05) comes before the effect system (06).** Tests are the
contract, so the hard module is not designed before we know how we prove it
works. This ordering also surfaces a design constraint early: mutation testing
requires the core suite to run in seconds, which constrains the core itself, not
just the tooling.

**The turn state machine (04) precedes the effect system (06).** Effect hooks
cannot be designed without the turn loop's anchor points being fixed first.

---

## Fidelity oracle — scope limit

The oracle is `@pkmn/sim` in its gen4 mod, exclusively. Divergences between
Showdown and the original cartridge are accepted. This makes the differential
fully automatable, with no human judgement in the loop.

It covers **battle mechanics only**. Capture, XP curves, EV gain, encounter
tables and evolution have no oracle and fall back on publicly documented
formulas plus hand-derived vectors — a weaker test pillar, accepted knowingly.
Spec 02 records this.
