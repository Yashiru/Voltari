# 0003 — No Fairy type

**Status:** Accepted
**Date:** 2026-09-07

## Context

The initial draft asked for a Gen 4 mechanical base plus the full 18-type chart,
including Fairy and all its interactions.

## Decision

The type chart is Gen 4 only. No Fairy type. The chart stays data-driven so it
can grow later, and no structure hardcodes the number of types.

## Options rejected

- **Gen 4 chart plus a Fairy row and column.** Looks like a small addition, but
  Fairy arrived in Gen 6 alongside other chart changes (Steel losing its Ghost
  and Dark resistances) and a different critical-hit multiplier. "Gen 4 + Fairy"
  is not a coherent generation; each Gen 4 / Gen 6 seam would need arbitrating
  one by one.
- **The full Gen 6 chart.** Coherent, but it drags in mechanics that contradict
  the Gen 4 target.

## Consequences

The fidelity target stays a single coherent generation, which keeps the oracle
usable as-is: `@pkmn/sim`'s gen4 mod has no Fairy either, so engine and oracle
agree by construction rather than by patching.
