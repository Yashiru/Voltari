# 0024 — The seed is scattered before it becomes generator state

**Status:** Accepted
**Date:** 2026-09-08
**Refines:** decision 0010 (semantic decision interface)

## Context

`VltSeededDecider` loaded its seed straight into xorshift32 state. xorshift32's
first output is a simple function of that state, so consecutive seeds produced
correlated first draws.

Measurably so. Asking seeds 1 to 12 for a speed tie returned `010101010101` —
the winner was the seed's low bit.

The fuzzer walks seeds 1, 2, 3, … So half of its speed ties were settled by the
case number rather than explored, and no test could have noticed: every case
still passed, deterministically, for the wrong reason.

It surfaced from an exhaustive mutation pass. `speed_tie` had a surviving
mutant, and printing the sequence to write a test against it showed the
alternation. The mutation harness did not find this; it pointed at the one
place where looking would.

## Decision

The seed passes through a splitmix32 finalising round before it becomes state:
one avalanche step, then xorshift generates as before.

Seeding is where the defect was. The generator is unchanged, and remains an
implementation detail behind the decision interface.

## Options rejected

**Warming up the generator** — discard the first N outputs after seeding. One
line, no new arithmetic. Rejected because N would be picked by eye: nothing
says how many outputs it takes for the correlation to wash out, and "measured,
not asserted" applies to a fix as much as to a claim of speed.

**Fixing it in the fuzzer**, by drawing well-spread seeds instead of counting
from one. The core would not move and no existing replay would change. Rejected
because the weakness would stay in the generator for every other caller — a real
battle seeded from a clock or an incrementing identifier would meet it again.

## Consequences

**Every seeded sequence changes.** Committed fuzz cases, seeded replays and the
`--seed` ordering of the mutation harness all produce different results than
before this entry. That is the cost of the fix and it is paid once; there are no
recorded regression seeds yet that would have to be re-derived.

The 120 generated battles were re-run and hold. They are now different battles
than the ones the invariants had been checked against, which is the point.

A test pins the decorrelation directly: strict alternation would give zero
repeats across consecutive seeds, and the guard fails well before that.
