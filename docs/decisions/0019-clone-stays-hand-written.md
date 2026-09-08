# 0019 — `clone()` stays hand-written, agreement guaranteed by test

**Status:** Accepted
**Date:** 2026-09-08
**Closes the open point in:** decision 0011, spec 03

## Context

Decision 0011 made the battle state mutable with a deep copy at the turn
boundary, and left one question open: `clone()` and serialisation do the same
job, so deriving the first from the second would satisfy "one concept, one
implementation" and make drift impossible.

It was deferred explicitly for measurement rather than settled on intuition.

## Measurement

Measured on a realistic state — two sides, six creatures each, four moves each,
two slots per side — over 5000 iterations
(`tools/bench/state_copy_bench.gd`):

| Mechanism | Per copy | Ratio |
|-----------|----------|-------|
| `clone()` | 97.4 µs | 1.00 |
| `from_dict(to_dict())` | 155.3 µs | 1.59 |

At one copy per turn boundary, that is 58 ms per thousand turns: irrelevant to a
single battle, material under fuzzing. At 50 000 copies it is 4.9 s against
7.8 s, and the core suite budget is ten seconds (spec 05).

## Decision

`clone()` stays hand-written on every state class.

The argument for deriving it was that two mechanisms drift apart. That risk is
covered instead by a test — `test_the_two_copy_mechanisms_agree` fails the
moment the two produce different results — which buys the same guarantee without
paying for it on every turn.

## Options rejected

- **Deriving `clone()` from a serialise round trip.** One mechanism, drift
  impossible by construction rather than by test, one fewer method per class.
  Rejected on the measurement: 1.59× on the core's hottest path, paid by exactly
  the workload the budget is tightest for.
- **Deriving now and optimising later.** YAGNI applied. Rejected because the
  rewrite would land under performance pressure, on a core much larger than
  today's.

## Consequences

Two methods per state class, kept honest by one test rather than by discipline.

The general shape is worth keeping in mind: "one concept, one implementation" is
about not having two ways to *do* something, and a test that pins two
implementations to the same result is a legitimate way to satisfy it when the
duplication buys something measurable.
