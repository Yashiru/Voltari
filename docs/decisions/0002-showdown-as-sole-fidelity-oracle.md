# 0002 — `@pkmn/sim` gen4 as the sole fidelity oracle

**Status:** Accepted
**Date:** 2026-09-07

## Context

Battle mechanics target Gen 4 behaviour. Since the IP is fully original, no
recorded Gen 4 output exists for our species and moves, so equivalence tests can
only target *procedures* — damage, stats, XP curves, resolution order — against
generated vectors. That requires choosing an oracle.

## Decision

`@pkmn/sim` in its gen4 mod is the oracle, **exclusively**. Vectors are generated
from it and committed as JSON fixtures, so the test suite needs no Node toolchain
to run. Divergences between Showdown and the original cartridge are accepted.

`gen4-deviations.md` is created empty: the escape hatch exists and is tested from
day one, but there is no deviation list to start with.

## Options rejected

- **The pokeplatinum decomp as oracle.** Closer to the cartridge, but it is prose
  to be read rather than an executable reference, so every vector would require
  human derivation and human judgement.
- **Decomp as arbiter, Showdown as generator.** Rigorous, but it reintroduces
  case-by-case judgement precisely where we wanted automation.

## Consequences

The differential becomes fully automatable with no human judgement in the loop:
the question is never "is this a Gen 4 bug?" but only "what does the oracle do?".

The oracle covers **battle mechanics only**. Capture, XP curves, EV gain,
encounter tables and evolution have no oracle and fall back on documented
formulas plus hand-derived vectors — a weaker test pillar, accepted knowingly.

The fidelity target is properly named "the gen4 mod of `@pkmn/sim`", not "Gen 4".
Showdown-derived data keeps its MIT attribution.
