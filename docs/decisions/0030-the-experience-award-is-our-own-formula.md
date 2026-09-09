# 0030 — The experience award is our own formula

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 10, section 4

## Context

Progression has no oracle: spec 02 limits `@pkmn/sim` to battle mechanics and
Showdown models no experience at all. The growth curves could therefore be taken
from a published source and verified against it (decision 0031). The award —
what defeating a creature is worth — is game logic, not data, and no source
publishes it as a table.

Writing it from memory was rejected. The same session had just shown why: the
curve formulas disagree with their own tables at level 1, by −54 in one case, and
only checking found that.

So it is authored instead. There is nothing to reproduce, and therefore nothing
to get wrong about somebody else's game.

## Decision

    XP = (a × b × L) / (5 × s) × ((2L + 10)^2.5 / (L + Lp + 10)^2.5) + 1

`a` is 1 wild, 1.5 for a trainer's; `b` the defeated species' base yield; `L` its
level; `Lp` the earner's; `s` how many share.

**The ratio is the design.** Beating something above your level pays sharply
more; beating something below collapses. Grinding on weak targets is
discouraged by arithmetic rather than by a rule saying so, and the exponent is
the lever that sets how steep that is.

### Rounding: one truncation, at the very end

Everything — including every multiplicative modifier — composes as floating
point. Then `+1`. Then a single `floor`.

Rounding per modifier would drift, which is the reasoning `VltDamageModifiers`
already follows for damage: ratios compose before the stage runs, because each
application would round again and change the result. The `+1` landing before the
truncation is what guarantees a fight is never worth nothing.

### The exponent is written as x² × √x

Not `pow(x, 2.5)`. IEEE-754 **requires** `sqrt` to be correctly rounded and
does **not** require it of `pow`, so two platforms may return results differing
in the last bit — enough, after multiplication, to fall on either side of the
truncation and pay one XP more or less.

`x² × √x` is the same value by operations the standard pins down.

### Floating point, here, on purpose

Spec 08 bans it from the damage pipeline, where the arithmetic must agree with an
oracle bit for bit. This formula answers to nobody, and the exponent is
irrational — integers cannot express it. The ban is about fidelity, not about
floats, and there is no fidelity claim to make here.

### Bounds on the base yield

**1 to 1000**, validated by the build. Wide on purpose: `b` is a design lever and
the check exists to catch a stray zero or an extra digit, not to express taste.
The intended bands are roughly 40–70 unevolved, 150–250 fully evolved, 300+ for
something meant to feel like an event.

## Consequences

At `b = 200`, a level 50 creature beating another level 50 earns 2001, against
7651 needed for the level on a `medium_fast` curve — about four fights. The same
creature farming level 5 targets earns 5. That is the intended shape, and the
figures are recorded so a later tuning pass can see what it is changing from.

Nothing automatic will catch a mistake in this formula; there is no differential
for it. Its guard is the shape tests of spec 10 section 9 — that the award climbs
with the defeated level, that punching up pays more than punching down, that two
half-modifiers give back the whole.
