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

The repository holds specifications only. There is **no Godot project, no test
suite and no CI yet** — spec 01 defines them. Do not invent or document commands
that do not exist; if you need one, it means spec 01 needs writing first.
