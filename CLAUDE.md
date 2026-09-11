# Voltari

Game engine for an original monster-catching RPG (capture, collection, turn-based
combat), built in Godot 4 / GDScript. Battle mechanics target Gen 4 behaviour.
The IP is 100% original — no third-party assets, names or code.

The project is in its **specification phase**. Architecture is settled before
implementation. No gameplay code lands ahead of a validated spec.

---

## Before you start

Read these, in order, before touching anything:

1. `docs/architecture/layers.md` — the layered decomposition and its normative
   rules (core purity, slots, PvP constraints)
2. `docs/specs/README.md` — the ordered specification plan and what is settled
3. `docs/decisions/` — the *why* behind each structuring decision
4. `git log` and the current branch — what has already landed

Do not restate these documents here or elsewhere. Link to them.

---

## Decision gate

The single most important rule. **Autonomous on execution, validated on decisions.**

**Do it yourself, no need to ask:**

- Create a branch, commit, run the test suite and CI checks
- Implement what an already-validated spec describes
- Reuse or extend an existing helper
- Fix a failing test, fix a lint error
- Local refactors that introduce no new abstraction

**Stop and ask an interactive question:**

- Any architecture choice
- Any new abstraction — class, interface, pattern, indirection
- Any new library or dependency
- Any public API change
- Any deviation from a spec, or anything a spec does not cover
- Anything touching the simulation core or the fidelity contract
- Introducing a second way to do something the codebase already does

When asking, present the options and their trade-offs. **Do not decide alone.**
Passing tests does not justify an abstraction.

---

## Workflow

**Always branch before starting any work, however small.** Never work directly on
the default branch.

```
<type>/<short-slug>     feat/ fix/ docs/ refactor/ test/ chore/
```

Commit autonomously, cleanly, often, one concern per commit. Messages in English,
imperative mood, `type: subject`.

**Before opening a PR, the full test suite and every CI check must pass locally.**
No PR on red. Keep diffs small and reviewable — the maintainer reviews everything,
so do not produce faster than one human can read.

---

## Code standards

**Static typing is mandatory, everywhere.** `var x: int`, typed parameters, typed
returns. Not a comfort feature: it unlocks faster bytecode paths and it is what
makes rigorous review possible.

**Read before you write.** Never copy-paste existing logic. Search the codebase
for an existing helper before writing a new one. Duplicated logic is a defect.
Reusing or extending existing code is autonomous; creating a new abstraction to
remove duplication goes through the decision gate.

**One concept, one implementation.** Never two ways to do the same thing, never
the same mechanism implemented in two files.

**Boring code by default.** Idiomatic, conventional GDScript. No metaprogramming,
no cleverness. Readability and long-term maintainability by a human always win
over concision or elegance.

**Performance is measured, not asserted.** Static typing is the standing
discipline. Anything beyond it — including dropping to Rust via gdext — requires
a profiler trace proving a hot path first. This is turn-based; assume there
isn't one.

**Robustness is enforced, not hoped for.** The core is pure computation with
bounded invariants. Assert them.

**Document the why.** Every structuring decision gets a short entry in
`docs/decisions/`: context, options rejected, reason for the choice. Code
captures the what; the journal captures the why.

---

## Fidelity and testing

The behavioural oracle is **`@pkmn/sim` in its gen4 mod, exclusively**.
Divergences from the original cartridge are accepted, which makes the
differential fully automatable with no human judgement in the loop. The oracle
covers **battle mechanics only** — capture, XP curves, EV gain, encounter tables
and evolution fall back on documented formulas plus hand-derived vectors.

Three test pillars for the core:

1. **Differential** against generated oracle vectors — zero undeclared divergence
2. **Invariants under fuzzing** — HP bounded, no deadlock, determinism at fixed
   seed, ordering preserved
3. **Mutation testing** — the real robustness metric, and where the numeric
   target lives

Line coverage is a CI floor, not a goal.

The core's purity rule is what makes all three feasible — see
`docs/architecture/layers.md`. Never weaken it for convenience.

---

## Clean room

No third-party code enters this repository, not even partially. Reference
implementations are read as behavioural documentation only. Showdown-derived data
keeps its MIT attribution.

---

## Language

Code, identifiers, filenames, commits, comments and documentation: **English**.
Conversation with the maintainer: **French**.

---

## Current state

**Every spec in the plan is written**: 01 to 18. Spec 19, networking and PvP,
is deferred by design — see `docs/specs/README.md`.
Decisions 0001 to 0052 are recorded in `docs/decisions/`.

**The simulation core is implemented and oracle-backed**: battle state, the
semantic decision interface, the battle log, the turn state machine, the effect
system, Gen 4 damage and stat formulas, plus the differential harness and the
invariant fuzzer.

**Above it**: progression and the post-battle pipeline, capture, the battle AI,
the save format, the overworld with its encounters, and event scripting with
quest flags. Content is authored one file per entity under `content/`, with a
Node build that validates it.

**Two suspendable machines, one shape** — turn resolution (decision 0012) and
event runs (decision 0044). Both advance until they need an answer, say what they
want, and are resumed. Neither uses `await`. The battle log reader is the third
thing that stops and continues and it *does* use `await` — decision 0050 records
why the reason behind the other two does not reach it.

**Four decision vocabularies** — battle, generation, policy, encounter — kept
disjoint by a meta-test (decision 0029). One generator backs them all.

**The purity lint covers `core/`, `deciders/`, `rules/` and `save/`.** `world/`
and `platform/` depend on the engine on purpose (decisions 0038 and 0040); that
exemption is stated in spec 01, not inferred.

**Creatures are rigged 3D, one rig each** (decisions 0020 and 0045 — the
pixel-art direction and the archetype-skeleton mitigation are both superseded and
should not be reintroduced from older notes). A pipeline outside the repository
takes a rigged FBX to a ready-to-instance `.tscn`; spec 16 describes the contract
it produces.

**The creature models are committed, through LFS.** 897 of them under
`game/assets/species/`, with `.gitattributes` sending every binary to LFS — a
`.glb` is already compressed, so an ordinary commit of one is the whole file
again, kept forever (decision 0071, which supersedes half of 0027).

**The tile pack is still quarantined.** `game/assets/species/brawl_arena/` and
the `.meshlib` built from it are Unity Asset Store packs: licensed to use in a
game, not to redistribute, and a repository redistributes. The guard of decision
0027 now watches those two paths and refuses them in the index, the tree, the
whole history and every export preset. Never stage anything under them, and
prefer path-scoped `git add` over `-A` at the repository root.

**Presentation lives in `game/presentation/`**, not in the addon: it carries this
game's art direction, so it is not the reusable engine (decision 0046). The
creature runtime, the shaders, the clip vocabulary and the manifest loader are
there. `tools/budget/` measures assets against provisional device tiers and
refuses nothing (decision 0048).

**What does not exist**: UI, audio, input, any authored map, any fakemon, and
any presentation manifest — the overworld is tested on fixture maps built in
code, the presentation on a generated `.glb` fixture, and `game/maps/` and
`content/presentation/` are both empty on purpose.

Requires Godot 4.7.2, Node 22 and **Git LFS** — the creature models are 1.7 GB of
LFS objects, and a clone without it gets 130-byte pointer files that Godot cannot
import. gdUnit4 is not vendored — install it into `addons/gdUnit4/` before running
tests locally. CI installs it automatically at the version pinned in
`.github/workflows/ci.yml`.

Core purity lint:

```bash
node tools/purity-lint/purity-lint.mjs
```

Content build — regenerate after editing anything in `content/`, and commit the
result. CI fails if the committed payload is stale:

```bash
npm --prefix tools run content:build
```

Test suite:

```bash
GODOT_BIN=$(which godot) ./addons/gdUnit4/runtest.sh --headless --ignoreHeadlessMode --continue -a tests
```

`--ignoreHeadlessMode` is required: gdUnit4 refuses headless mode by default
because UI tests need a display. The core is pure computation, so headless is
correct here.

All three must pass before opening a PR.
