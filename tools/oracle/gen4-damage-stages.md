# Gen 4 damage stages — extracted from the oracle

**Oracle:** `@pkmn/sim` 0.10.11, gen4 mod
**Extracted:** 2026-09-07
**Method:** behavioural reading of the oracle's gen4 damage override, per
`docs/specs/08-formulas.md` section 4. No oracle code is reproduced here or
anywhere in the repository.

This is a **derived artefact**, not a specification. It is regenerated, reviewed
and re-committed when the pinned oracle version changes (spec 02, section 8).

---

## Stage sequence, after base damage

| # | Stage | Nature |
|---|-------|--------|
| 1 | Burn — physical damage halved when the attacker is burned, unless its ability suppresses this | conditional halving |
| 2 | Modifier phase 1 — screens and comparable effects | modifier anchor |
| 3 | Spread — multi-target reduction in doubles | modifier |
| 4 | Weather | modifier anchor |
| 5 | **Constant `+2`** | addition |
| 6 | Critical hit — doubling in Gen 4 | modifier |
| 7 | Modifier phase 2, **then floor** | modifier anchor + rounding |
| 8 | Random roll, 85–100 — *explicitly not a modifier* | forced decision |
| 9 | STAB — ×1.5, itself modifiable | modifier anchor |
| 10 | Type effectiveness — repeated doubling or halving, exponent clamped to `[-6, +6]` | integer steps |
| 11 | Final modifier | modifier anchor |
| 12 | Floor, with a **minimum of 1** | rounding + clamp |

## What this settles

**The `+2` sits at stage 5** — after weather, before the critical hit. Not in the
base damage, which is where anyone reconstructing this from memory would put it.
This single placement is the case for decision 0018: a formula written from
recollection into the fidelity reference would have been wrong, in the document
meant to settle disputes.

**Stage 8 is a decision, not a modifier.** The oracle marks it as such
explicitly, which matches the rule in spec 06: the pipeline never invents an
ordering, and the random roll is answered by the decision policy rather than
computed inline.

**Stage 10 is repeated integer doubling and halving**, not one multiplier. This
is the integer discipline of spec 08 section 3 appearing in the oracle itself:
`value * 3 / 2`, never `value * 1.5`.

**Stages 7 and 12 are where rounding happens.** Rounding anywhere else changes
the result.

## Empirical confirmation

`generate-damage-vectors.mjs` forces each of the sixteen rolls and records the
full spread. Both generated vectors show a min/max ratio of 0.84–0.85, the
signature of the 85–100 roll, and the flooring plateaux that stage 12 predicts.

## Trap encountered

Answering *every* chance with "no" also answers the accuracy roll, so every move
misses and the vectors silently come out as zero damage. Decisions must be
answered **per kind** — accuracy always hits, critical never, secondary never —
which is the empirical case for the semantic interface of decision 0010.
