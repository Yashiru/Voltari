# 08 — Formulas

**Status:** Draft
**Depends on:** specs 02, 03, 06, 07; decisions 0002, 0015

The arithmetic heart: damage, stat derivation, accuracy, critical hits, speed
ordering, stat stages, type effectiveness.

This document defines the **shape and the discipline** of those formulas. It
deliberately does not contain them.

---

## 1. Why the formulas are not written here

The formula exists in two places already: the code that implements it, and the
oracle vectors that verify it. Restating it in prose would make three, and the
prose is the one nobody runs — so it is the one that silently goes stale, in the
document that is supposed to settle disputes.

The same reasoning already governs spec 03 (which refuses to enumerate effects)
and spec 04 (which refuses to name them). It applies with more force here,
because a formula transcribed from memory into the fidelity reference would be an
unverified assertion sitting exactly where verification is supposed to live.

**The truth is the code plus its vectors.** This document says how they are
obtained and what rules they obey.

## 2. Staged pipeline

Every formula is a sequence of **stages**. Each stage is an anchor (spec 06);
modifiers attach to stages and never move across them.

The stage enumeration is the artefact that closes the two enumerations left open
elsewhere: the anchors of spec 06 and the event vocabulary of spec 07. It lives
in code as a single enum — one source of truth, referenced by both.

The stage list is not a design choice. It is **extracted from the oracle**, and
the shape of the formula follows from what the oracle actually does.

## 3. Integer arithmetic discipline

Gen 4 arithmetic is integer arithmetic with rounding at each step. The result
depends on that rounding, so the discipline is not stylistic:

- **No `float` anywhere in the damage path.** A multiplier of 1.5 is written
  `value * 3 / 2`, never `value * 1.5`.
- Rounding happens where the oracle rounds, not where it is convenient.
- Type effectiveness is carried as an integer ratio, never as a decimal.
- Intermediate values are never carried at higher precision "for accuracy" —
  precision loss at each step *is* the specification.

A single `float` in this path is a fidelity defect that vectors may not catch on
the cases we happened to generate. It is worth an automated check: extending the
purity lint to reject `float` in the formula module is an open point below.

## 4. Extraction protocol

For each formula:

1. **Read** the oracle's behaviour for that computation. Reference
   implementations are behavioural documentation and nothing else; no code is
   copied, not even partially.
2. **Record** the stage list as an enum entry per stage.
3. **Generate** vectors covering every stage and every branch within it
   (spec 02).
4. **Implement** against those vectors.
5. **Declare** any divergence in `docs/gen4-deviations.md`, with its asserting
   test. There is no undeclared divergence.

Step 3 precedes step 4. A stage without vectors is not implemented, because there
would be nothing to distinguish a correct implementation from a plausible one.

## 5. Scope

| Formula | Oracle-backed |
|---------|---------------|
| Damage | yes |
| Stat derivation from base stats, IVs, EVs, nature | yes |
| Accuracy and evasion | yes |
| Critical hits | yes |
| Speed ordering and priority | yes |
| Stat stage multipliers | yes |
| Type effectiveness | yes |

Everything in this table is battle mechanics and therefore covered by the oracle.
Capture, XP curves, EV gain, encounter tables and evolution are **not** — they
fall outside `@pkmn/sim`'s scope entirely (spec 02, section 9) and are specified
in specs 10 and 11 against documented formulas and hand-derived vectors.

No formula in this document may claim oracle backing without a generated vector
proving it.

## 6. Type chart

Gen 4 only, no Fairy type (decision 0003). The chart is **content data**, loaded
like any other (spec 09), never hardcoded, and no structure assumes a fixed
number of types — the chart is expected to grow later.

---

## Open points

- The stage enumeration itself, produced by section 4 and closing specs 06
  and 07.
- Extending the purity lint to reject `float` in the formula module. The lint
  currently targets whole directories; this rule needs a narrower scope, since
  `float` is legitimate elsewhere in the core.
- Whether stat stage multipliers are a lookup table or a computation is settled
  by whichever matches the oracle's rounding exactly.
