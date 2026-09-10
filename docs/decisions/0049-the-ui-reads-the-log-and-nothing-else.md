# 0049 — The battle UI reads the log and nothing else

**Status:** Accepted
**Date:** 2026-09-09
**Refines:** decision 0017 (per-event visibility with transformation)
**Recorded in:** spec 17, sections 1 and 8

## Context

Decision 0017 gives every event a visibility tag and gives each side its own
filtered log: an opponent sees a health proportion rather than exact HP.

The battle state is sitting right there, fully typed and much easier to read. A
health bar is two lines from it and a dozen from the log.

## Decision

**Everything the player sees of a battle is derived from the log.** Nothing under
the reader may reference `VltBattleState`, and that is enforced by a lint over
its directory rather than by intent.

> **Narrowed on 2026-09-10, while building it.** This first said "the battle
> state classes at all", and the lint caught the reader on its first run — it
> holds the viewpoint's own party, because the log does not announce your own
> creature's moves and correctly does not: they were never a battle event.
>
> The rule names the state and not the creatures in it, and the difference is the
> whole point. **A state is reach**: from one you can read the opponent. A
> creature handed in is your own, and passing it bypasses no filter. The wording
> over-reached; the purpose is unchanged.

## Why the easy path is the wrong one

The filter is not a display convenience. It is the mechanism that makes PvP
possible without rewriting the presentation layer, because each side is handed
only what it is entitled to know.

**A HUD that read the state would walk around the filter without anybody
deciding to.** It would work perfectly in single player, and the day a second
player connected it would already be showing them the opponent's exact HP. That
is not a defect discovered in testing; it is a rewrite deferred until the worst
moment to pay for it.

## Options rejected

**The log for animation, the state for the HUD.** The pragmatic split, and the
one that gets written by default. Rejected above: the HUD is exactly the part
that leaks, because it displays continuous values rather than moments.

**Filtering the state as well as the log**, so reading it is safe. Rejected as
two mechanisms for one rule — and the second would have to be kept in step with
the first by hand, which is how they diverge.

## Consequences

**The reader rebuilds what it shows by replaying events.** That is affordable
only because spec 07 made events carry resulting values rather than deltas:
replay assigns, it does not recompute. Had the log been deltas, this decision
would have been much more expensive and probably wrong.

**A HUD element with no event behind it cannot exist.** Which is a design
constraint on the UI, and a good one: it is caught the moment somebody tries,
rather than the first time a mechanic changes underneath it.

The spec's test for this is deliberately the awkward direction — give the reader
only what one side may see and require the display to be complete. A test that
fed it everything would pass whatever the reader touched.
