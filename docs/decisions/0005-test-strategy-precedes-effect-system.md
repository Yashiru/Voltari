# 0005 — Test strategy is specified before the effect system

**Status:** Accepted
**Date:** 2026-09-07

## Context

The effect system is the architectural risk of the project: moves, abilities,
items, statuses, stat stages, weather, hazards, priority, and above all the
ordering rules between them. The initial draft required 100% line coverage on
that module, non-negotiable.

## Decision

The core test strategy (spec 05) is written *before* the effect system (spec 06).
Line coverage is demoted to a CI floor. The real contract is three pillars:

1. **Differential** against generated oracle vectors — zero undeclared divergence
2. **Invariants under fuzzing** — HP bounded, no deadlock, determinism at fixed
   seed, ordering preserved
3. **Mutation testing** — the real robustness metric, and where the numeric
   target lives

## Options rejected

- **100% line coverage as the objective.** A necessary floor, but a weak metric
  for an interaction engine: full line coverage says nothing about combinations
  of effects, which is exactly where the defects live.
- **Designing the effect system first, testing after.** Tests are the contract;
  designing the hard module before knowing how it is proven correct inverts that.

## Consequences

Mutation testing requires the core suite to run in seconds — a design constraint
on the core itself, not just on tooling. Property-based generators and the
mutation harness are written in-house; no mature GDScript library exists for
either, and that cost is accepted.
