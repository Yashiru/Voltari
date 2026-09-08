# 0029 — Generation decisions get their own interface

**Status:** Accepted
**Date:** 2026-09-08
**Refines:** decision 0010 (semantic decision interface)
**Recorded in:** spec 10, section 3

## Context

L1 carries the same purity constraint as the core: it draws no numbers. But a
creature being born needs IVs, a nature and a gender, and those are drawn.

Decision 0010 already solved this shape for the core — ask named questions, let
something else answer. The question was whether to widen `VltDecider` or apply
the pattern a second time.

The maintainer delegated this one, asking for whichever answer was best for
robustness and architecture.

## Decision

**A second interface**, in L1, following the same pattern. The two vocabularies
are disjoint by construction: no question appears in both, and a meta-test
asserts it.

One seeded generator may back both. Separate interfaces do not require separate
sources of randomness.

## Options rejected

**Widening `VltDecider`.** One interface project-wide, one generator, and a
birth replays exactly like a turn — genuinely attractive.

Rejected because of what `VltDecider` is. One of its implementations encodes the
policy shared with the oracle, and it is the class the whole fidelity contract
rests on (spec 02, decision 0009). Adding `individual_value` would oblige the
scripted decider to answer questions the oracle never asks, putting dead surface
in the one place that must stay exactly as wide as what both engines agree on.
The reproducibility it buys is also worth less here than it looks: a creature's
IVs are rolled once and stored, not re-derived from a replay.

**Passing the values in as parameters.** L1 stays purely functional and
trivially testable, and nothing new is declared.

Rejected because the drawing does not disappear — it stops being anybody's
declared responsibility. An undeclared draw is made with whatever RNG is
nearest, which is the exact failure the purity rule exists to prevent. Displacing
a problem out of the layer that owns it is not solving it.

## On "one concept, one implementation"

Two interfaces of the same shape look like the second way of doing one thing the
standards forbid. They are not.

That rule is about **one job with two mechanisms**. Here there is one pattern
applied to two disjoint jobs, with a vocabulary each and a test that keeps them
from overlapping. If a question ever needed to be asked in both, that would be
the signal to reconsider — and the meta-test is what would raise it, rather than
the two drifting together unnoticed.
