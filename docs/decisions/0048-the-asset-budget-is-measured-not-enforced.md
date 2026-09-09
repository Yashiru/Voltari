# 0048 — The asset budget is measured, not enforced

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 16, section 7

## Context

The game targets mobile. Triangles, texture memory and bone counts have ceilings
somewhere, and a roster of creatures is where they get spent.

The standing rule is that performance is measured, not asserted — anything beyond
static typing needs a profiler trace proving a hot path first. That rule was
written about code. An asset budget is a different animal: it is a design
constraint, and the trace that would justify it cannot exist until there is a
roster to trace.

## Decision

**The build reports; it refuses nothing.** Triangles, texture sizes, bone counts,
per asset and as a roster total.

## Options rejected

**A ceiling that refuses an over-budget asset.** The argument for it is real and
was nearly decisive: the failure is **cumulative**. No single creature breaks the
frame budget, the roster does, and by the time a device says so the fix is
re-authoring assets rather than changing code.

Rejected because the ceiling would have to be invented. Nobody has profiled this
game on a target device, so any number written today is a guess wearing the
authority of a build failure — and a wrong ceiling is worse than none, because it
gets worked around rather than questioned.

**No budget at all until a device speaks.** The strictest reading of the standing
rule. Rejected because the first creatures will be authored long before that
profile exists, and authoring them blind means re-authoring them later.

## Consequences

**A number nobody is obliged to respect is a number nobody respects.** That is the
risk, stated rather than hoped away.

What makes it survivable is that the report is cumulative as well as per-asset,
so the trend is visible long before a device is available. The thing to watch is
not any one creature but the total moving.

If the trend turns out to be ignored, the ceiling is one line in the build. This
decision should then be superseded by one that carries an actual measurement —
which is the form the standing rule asks for, and which will finally be possible
to satisfy.
