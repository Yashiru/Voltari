# 05 — Core test strategy

**Status:** Draft
**Depends on:** specs 02, 03, 04; decisions 0001, 0005, 0009, 0010, 0011

How the core is proven correct. Written **before** the effect system (decision
0005): tests are the contract, so the hard module is not designed before we know
what proving it correct means.

---

## 1. The contract

Line coverage is a **CI floor, not an objective**. Full line coverage says
nothing about combinations of effects, which is exactly where the defects live.

Three pillars carry the real weight:

| Pillar | Answers | Gate |
|--------|---------|------|
| Differential | Does it match the oracle? | Zero undeclared divergence |
| Invariants under fuzzing | Can it be broken? | 100% pass |
| Mutation testing | Would we notice if it broke? | Score target, on demand |

## 2. Pillar 1 — Differential

Spec 02 defines the oracle, the fixture format and the decision policy. This
section covers only how tests consume them.

- **Procedure vectors** are table-driven: one test per fixture file, one case per
  vector, comparing all sixteen damage rolls at once rather than a single value.
- **Battle differential** replays each scripted battle through the core with the
  scripted decider, projects the log, and compares event by event against the
  stored oracle projection.

A vector that fails is a defect until it appears in `docs/gen4-deviations.md`
with its own asserting test. There is no third state.

## 3. Pillar 2 — Invariants under fuzzing

The fuzzer generates seeded, reproducible battles: random teams, random legal and
illegal commands, random suspension answers. It exists to violate the invariants
below.

### Invariants

| # | Invariant |
|---|-----------|
| 1 | HP is always within `[0, max]` |
| 2 | A creature at 0 HP is fainted, and a fainted creature is at 0 HP |
| 3 | Stat stages stay within `[-6, +6]`, PP within `[0, max]` |
| 4 | Resolution always terminates: it returns `Complete`, or a `NeedsInput` naming at least one answerable request |
| 5 | A battle reaches an end state within a bounded number of turns |
| 6 | Determinism: identical state, commands and decider produce identical `state'` and log, bit for bit |
| 7 | Purity: `resolve` does not mutate its input state |
| 8 | Replaying the log onto the initial state reproduces `state'` |
| 9 | Serialisation round-trips: `deserialise(serialise(state)) == state` |
| 10 | Any malformed command is rejected explicitly, never crashes and never corrupts state |
| 11 | Slot-scoped state is empty for an empty slot |

Two of these earn their place beyond the obvious:

- **7** tests decision 0011 directly. The fuzzer keeps a copy taken before the
  call and asserts the input is untouched afterwards. Without it, the purity
  guarantee is a comment.
- **8** makes the *completeness of the log* testable. The UI and the differential
  both depend on the log carrying everything that happened; this is what turns
  that dependency into an assertion instead of a hope. It is the strongest single
  invariant in the list.

### Shrinking

A failing case is reduced by **delta-debugging**: commands and creatures are
removed while the failure persists, down to a minimal case, which is what gets
committed as a regression test.

This is cheaper here than it usually is, and for a structural reason — the core
is deterministic and replayable by construction, so replaying a truncated case is
trivial. It is a direct dividend of the pure-core architecture.

A minimised case is stored as `(seed, command sequence)` and becomes a permanent
fixture.

## 4. Pillar 3 — Mutation testing

Mutants are injected into the core; the suite must catch them. A surviving mutant
is a hole in the tests, not a bug in the code.

### Catalogue

Arithmetic and comparison operator swaps, boundary shifts (`<` / `<=`), boolean
negation, constant perturbation (`n` → `n±1`, `0`, `1`), statement removal, early
return.

### Cadence

**On demand only.** It is not a CI job and does not gate a pull request.

That keeps pull requests fast, but a metric nobody looks at drifts — which is
what already happened to line coverage. So the trigger is a written convention
rather than a habit:

> Mutation testing is expected to be run, and its score recorded in the pull
> request, for any change touching the effect system or the turn machine.

### Target

A **ratchet**, measured rather than chosen: the recorded baseline is **85.2%**
across **every mutation site in the purity-enforced layers** — 254 of 298, not a
sample — and it may not go down. See decision 0021 for why the target is a
measurement rather than a number.

**It ratchets across like populations.** Adding code adds sites, and a module
whose survivors are structurally unkillable lowers the percentage while losing
nothing: the figure went from 86.4% to 85.2% when the rules layer arrived, with
every one of its survivors an assert. Comparing raw percentages across different
populations does not answer the question the ratchet asks. When the site count
changes, re-establish the baseline and let the **survivor classification** below
carry the argument — a run whose survivors are all unkillable has lost no test,
whatever the percentage did.

Run it exhaustively — `--limit 9999`, no `--file`. It takes about fifteen
minutes and it replaces sampling entirely, so there is little reason to sample
the whole core any more. Narrow with `--file` only to iterate on one module.

**Do not read the remaining percentage as work left.** All 44 survivors are ones
no passing test can kill, and they account for exactly three kinds:

| Kind | Count | Why it cannot be killed |
|------|-------|-------------------------|
| Asserts | 27 | Abstract base methods and preconditions. The original aborts on the very input that would tell the mutant apart, so chasing these means testing that an abstract method is abstract. |
| Guarded comparisons | 13 | A `>` or `<` immediately under an `if a != b`. The operands are never equal there, so the two forms cannot differ. |
| Field defaults | 4 | Every constructor overwrites them before anything reads. |

So the figure is a **ceiling, not a milestone toward 100%**. A pass at the
ceiling and a pass that found nothing look identical: read the survivor list,
not the percentage.

**Sampling misjudges unpredictably, which is why exhaustive is the default.** A
hundred-mutant sample badly understated `effect_dispatch.gd` — the exhaustive
pass found 23 survivors there and a real defect (decision 0022). It was right
about `battle_state.gd`, `damage.gd` and `stats.gd`, each already at 100%. And
going exhaustive over the whole core surfaced survivors no sample had ever
shown, in `move_definition.gd`, `command.gd` and `seeded_decider.gd` — the last
of which led to decision 0024.

Narrow a pass to one module with `--file`, and raise `--limit` to cover it
exhaustively. A sampled score for a single file is noise: this one read 12
survivors when sampled across the core and 23 when the file was run in full.

**A module pass and a core sample answer different questions**, and neither
substitutes for the other. Covering `turn_engine.gd` took it from 86% to 94%
exhaustively and left the core sample sitting at 80%, because none of the
mutants it killed were among the hundred that sample draws. Read the core figure
as the ratchet and the module figure as the work.

## 5. Speed budget

Mutation testing multiplies suite runtime by the number of mutants: a five-second
suite with five hundred mutants is roughly forty minutes.

**The core suite must stay under ten seconds.** This is a design constraint on the
core, not on the tooling — it is why the core does no I/O, builds fixtures in
memory, and never touches the scene tree.

## 6. Tooling

- **gdUnit4** for the runner and assertions (decision 0006).
- **In-house** property-based generators, shrinker and mutation harness. No mature
  GDScript library exists for any of the three; the cost is accepted.
  Fuzzing lives in `tests/fuzz/`, its harness in `tests/support/`, and the
  mutation harness in `tools/mutation/`.
- **Nano Coverage** for the line-coverage floor only.

The suite stays hermetic: running it requires neither network nor npm. Oracle
vectors are committed (spec 02).

---

## Open points

- `effects/effect_dispatch.gd` holds twelve of the twenty-nine known survivors.
  Its ordering rules are the kind of logic that survives naive tests and decides
  battles, so it is the obvious next target.

## Settled

- **The mutation target**, per decision 0021: a ratchet on a measured baseline.
- **The shrinker is demonstrated**, not assumed: it runs against a predicate
  whose answer is known, because one that always returned its input would look
  like it worked.
