# 0021 — The mutation target is a ratchet, not a fixed number

**Status:** Accepted
**Date:** 2026-09-08
**Closes the open point in:** decision 0014, spec 05

## Context

Decision 0005 made mutation testing the real robustness metric and said the
numeric target lives there. Decision 0014 deferred the number until there was a
run to base it on, reasoning that an arbitrary gate is one that gets waived.

The harness now exists and has been run.

## Measurement

100 mutants sampled from 262 sites across the core, seed 31:

| | |
|---|---|
| Score | **71%** — 71 caught, 29 survived |
| Survivors in `effects/effect_dispatch.gd` | 12 |
| Survivors in `decisions/decider.gd` | 5 |
| Elsewhere | 12, spread across nine files |

An earlier 25-mutant sample scored 84%. The difference is sampling noise, and it
is the reason the target is not set from a small run.

## Decision

The target is a **ratchet**: the recorded baseline is 71%, and it may not go
down. A change that lowers it is either missing a test or removing one.

No absolute figure is fixed. A number chosen without evidence would be either
trivially met or routinely waived, which is exactly what decision 0014 wanted to
avoid, and the honest reference point is the measurement we have.

## Two categories of survivor, treated differently

**Unreachable by construction.** The five in `decider.gd` are the abstract base
class: every method asserts and returns a placeholder, so mutating the
placeholder changes nothing a test could observe. Chasing these would mean
testing that an abstract method is abstract.

**Genuine gaps.** The twelve in `effect_dispatch.gd` are not that. It is the
newest module and the least exercised, and the concentration says so plainly —
which is the harness doing its job: pointing at where the tests are thin rather
than reporting a number.

## Consequences

The score is recorded in the pull request for any change touching the effect
system or the turn machine (decision 0014), and compared against the baseline
rather than against an ideal.

`effect_dispatch.gd` is the known weak point and the obvious next target. Its
ordering rules — priority, then speed, then the deterministic tiebreak — are
precisely the kind of logic that survives naive tests and decides battles.

## Afterwards

The measurement above is kept as written, since it is what the decision was
taken on. **The live baseline is in spec 05** and moves as the ratchet turns; it
reached 80% once `effect_dispatch.gd` was covered.

That pass is also the evidence for the sampling caution above. Sampled across
the core, the file showed 12 survivors; run exhaustively it showed 23, and the
file score was 53% rather than the 71% the core-wide figure suggested. It also
found a defect rather than only thin tests — see decision 0022. A per-module
number needs a per-module run.

**A ratchet needs a fixed population, which was not obvious when this was
written.** Adding the rules layer added nineteen sites, every one of whose
survivors is an assert, and the figure fell from 86.4% to 85.2% without a single
test being lost. "It may not go down" only means anything between runs over the
same sites. Across a change in population, the survivor classification is the
argument and the percentage is just a summary of it.

**The two categories above turned out to be the whole story.** Once
`effect_dispatch.gd`, `turn_engine.gd`, `burn.gd`, `log_heal.gd` and
`log_move_used.gd` were covered, every survivor left in the sample was
unreachable or equivalent, and the score stopped at 84%. The ratchet should
therefore be read as "did this change lose a test", never as a distance from
100% — a run that reaches the ceiling and a run that found nothing look the
same, and only the survivor list tells them apart.
