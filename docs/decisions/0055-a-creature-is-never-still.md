# 0055 — A creature is never still

**Status:** Accepted
**Date:** 2026-09-10
**Settles:** an open point in spec 16, section 1
**Recorded in:** spec 16, sections 1 and 12

## Context

`CreatureBody.play` played the first take of a slot and stopped. Spec 16 left the
choice of take open on purpose, and the code said so:

> The first take, every time. Spec 16 leaves the choice open — at random, in
> rotation, or weighted — and picking randomly here would make a screen
> irreproducible before anybody had decided it should be.

Watching a real battle settled it. A creature played its entry clip and then
froze in its rest pose until it was hit — which does not read as a still frame,
it reads as a crash.

Every placeholder model carries two battle idles, `waitA` and `waitB`, so the
material for the answer was already there.

## Decision

**A clip that ends hands back to the idle, and the idle hands back to itself.**

The loop falls out of that rather than being written: nothing in the body knows
it is looping. It plays the idle when the model appears, and again whenever
anything finishes.

**A slot with several takes reaches past the first about one time in four.**
Weighted, not uniform and not in rotation, so a second idle is a flourish rather
than an alternation.

**The randomness is its own source**, a `RandomNumberGenerator` on the body. It
is never one of the decision vocabularies (decision 0010, decision 0029).

## Options rejected

**Setting the idle clip's loop mode.** One line, and the engine loops it. Rejected
because it mutates an imported resource shared by every instance of that species,
and because a looping clip cannot vary its take — which is the other half of what
was asked for.

**Rotating through the takes.** Deterministic, reproducible, no randomness at all.
Rejected on how it reads: two idles alternating is a two-beat rhythm, and a
viewer sees the pattern within seconds. The point of a second idle is that it is
not expected.

**Weighting per take in the manifest.** Author-controlled, and the right answer
eventually. Rejected as premature: nobody has authored a manifest by hand yet, so
the weights would be invented by the same person picking a constant, with a file
format added on top.

**Leaving it as it was until an art direction exists.** The position spec 16
took. Overtaken by the screen being used: a frozen creature is not a neutral
placeholder, it is a bug report.

## Consequences

**A screen is no longer reproducible frame for frame**, which is exactly what
spec 16 was protecting. It is accepted because the thing made irreproducible is
which breath a creature takes, and nothing observes it: no test asserts a frame,
the battle log is unaffected, and the vocabularies stay disjoint by construction
since this source is not one of them.

What a test can still assert is the *policy* — that the first take dominates, and
that a second take is reached at all — and that is what the suite does.

**`finished_playing()` is public.** The end of a clip is a signal, and a headless
test has no frames to wait for one in. The same door the signal comes through is
left open rather than a second path being written for tests.

**A creature with one take for a slot behaves exactly as before.** Which is every
slot except the idle, on every model there is.
