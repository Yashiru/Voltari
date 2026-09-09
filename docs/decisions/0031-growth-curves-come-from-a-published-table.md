# 0031 — Growth curves come from a published table, verified against its formula

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 10, section 9

## Context

Spec 10 asks for published formulas "transcribed once into code with the source
recorded next to them". For the experience curves there was no source at hand —
only recollection, in the one area of the project with no oracle to catch a
mistake.

## Decision

The six curves are seeded from **PokéAPI**, which publishes both the closed-form
formula and the level-by-level table for each one.

They are **verified, not trusted**: the seeding tool checks each of the four
closed-form curves against its own published formula at every level, and all six
against structure — one entry per level, starting at zero, strictly increasing.
It refuses to write when a check fails.

Fetched once and committed, which is also what PokéAPI's fair use policy asks:
"Locally cache resources whenever you request them." The suite stays hermetic and
never touches the network.

Only mechanical tables cross over. No names, in keeping with the clean room rule,
and the mapping between their curve names and ours stays in the tool — the same
arrangement the Showdown-derived type chart already uses.

## What the check found immediately

The formulas disagree with their own tables at level 1. `slow` gives 1,
`medium_fast` gives 1, `medium_slow` gives **−54**; every table says 0.

Level 1 is zero by definition — a creature starts there having earned nothing —
and the cubics simply do not govern it. The tables are right.

Transcribing from memory would have carried that error in silently, and nothing
downstream would have caught it. It is the clearest argument available for why
this decision is worth its cost.

## Options rejected

**Transcribing the formulas from knowledge**, marked unverified. Fastest, and the
project would have been playable sooner. Rejected because an unverified constant
in the area with no automatic net is exactly the assertion spec 08 refuses to put
where verification is supposed to live — and the level-1 discrepancy shows the
recollection would have been wrong.

**Waiting for a source the maintainer supplies.** Nothing unverified enters, but
the pipeline stops on a question that a fetch answers in seconds.

**Computing the tables from the formulas ourselves.** Removes the dependency
entirely. Rejected because two of the six curves are piecewise, so the formulas
would still have come from memory — and those two are precisely the ones this
decision cannot verify.

## Consequences

The two piecewise curves, `erratic` and `fluctuating`, have **structural checks
only**. That is stated in the generated file itself rather than left to be
assumed: a verification whose shape nobody can see is worth little.

The build re-checks the committed tables, since they are data now and an edit to
them has no other guard.

A second opinion sits in the test suite: it derives the four closed forms
independently rather than re-running the tool's arithmetic, so the two would have
to be wrong in the same way to agree.
