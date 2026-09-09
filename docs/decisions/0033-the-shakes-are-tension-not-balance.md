# 0033 — The four shakes are tension, not balance

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 11, section 3

## Context

The capture formula was supplied with a design rationale attached: that the
shake threshold's exponent bends the odds, so a middling modified rate `a` yields
"something lower than 50%" rather than 50%, making risky-but-possible captures
more common than the raw ratio suggests.

The formula is right. The rationale does not describe what it does.

## What the arithmetic says

    b = 1048560 / sqrt(sqrt(16711680 / a))

`16711680 = 255 · 65536` and `1048560 / 16 = 65535`, so

    b = 65535 · (a/255)^(1/4)

A quarter power, not the three-sixteenths the rationale named. Four independent
checks at `b/65536` therefore give back `(a/255)` — the raw ratio, unbent.

Measured against the exact floored implementation:

| `a` | P(capture) | `a/255` |
|-----|-----------|---------|
| 30 | 0.123 | 0.118 |
| 128 | **0.503** | 0.502 |
| 180 | 0.785 | 0.706 |

At `a = 128` the result is 50.3%, not "something lower".

## Decision

**The formula stands as written.** It is the behaviour of the reference games and
it is internally coherent; only the explanation was wrong, and the explanation is
what this entry corrects.

Stage 2 decides how many shakes are *seen* before a failure. It does not decide
how often capture succeeds. The balance levers are the two on `a` — the HP
fraction and the status bonus — and they are enough: weakening a target very
nearly triples the odds.

## Options rejected

**Bending the odds for real**, by raising the exponent so the net probability
falls below `a/255`. It would deliver what the rationale described. Rejected
because it departs from a formula with decades of play behind it, and the new
exponent could only be chosen by feel — there would be nothing to derive it from.

**Leaving the arithmetic unexamined and implementing the rationale's intent.**
Rejected on principle: the same session had already found that published curve
formulas disagree with their own tables at level 1, and that checking is what
found it.

## Consequences

If capture must ever be rarer than the ratio suggests, the exponent is the lever
and changing it is a change to spec 11 — not a tuning pass on content.

A test asserts the net probability equals `a/255` across the range. It is not
redundant with the formula: it is what would notice the day someone "improves"
stage 2 into a second curve without realising the first one was already flat.
