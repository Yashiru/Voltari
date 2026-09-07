# 0009 — Battle differential driven by a semantic decision policy

**Status:** Accepted
**Date:** 2026-09-07

## Context

Procedure vectors (damage, stats, speed) assert formulas but cannot assert
*resolution order* — which is the actual architectural risk of the project. The
only way to compare ordering against the oracle is to replay the same battle on
both engines.

Voltari uses its own RNG rather than reproducing the Gen 4 LCG, so seeds cannot
be shared with `@pkmn/sim`, and the two engines make their random calls in
different orders.

## Decision

Both engines are driven by the same **semantic decision policy** rather than by a
shared random sequence. They do not share random numbers; they share *answers*:
damage roll index, hit or miss, crit or not, secondary triggers or not, speed tie
winner, multi-hit count, status duration.

A battle fixture declares one policy for the whole battle, with targeted
overrides where the mechanic under test is itself the random one. On the oracle
side the policy substitutes `@pkmn/sim`'s PRNG; on our side it substitutes the
injected RNG stream.

Comparison happens on a **normalised projection** of both logs, with an explicit
ignore list for events that exist in only one vocabulary.

## Options rejected

- **Aligning the two RNG call sequences.** Would require reproducing Showdown's
  call order exactly, coupling our internals to a third-party implementation —
  fragile, and it inverts which engine is authoritative.
- **Reproducing the Gen 4 LCG.** Would allow cartridge-identical sequences, but
  it was already rejected: sequence identity has no value for original content,
  and it constrains the core for nothing.
- **Procedure vectors only.** Simpler, but resolution order — the thing most
  likely to be wrong — would never be compared to the oracle at all.

## Consequences

Two architectural constraints, both binding on specs written after this one:

- **Spec 03** — randomness must be injectable as a *decider interface*, not
  merely as a seeded generator, so a scripted policy can replace it wholesale.
- **Spec 07** — the battle log must be normalisable, and complete enough that a
  projection of it can be compared event by event.

Most differential battles end up RNG-free by construction (100% accuracy moves,
crits disabled, damage roll fixed). Damage exactness stays the job of procedure
vectors; the differential exists for ordering and interaction.

The ignore list is part of the fidelity contract, not an implementation detail:
an event silently dropped from the projection is a hole in the differential.
