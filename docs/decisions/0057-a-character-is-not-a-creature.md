# 0057 — A character is not a creature

**Status:** Accepted
**Date:** 2026-09-10
**Settles:** an open point in spec 16 ("characters, as opposed to creatures")
**Recorded in:** spec 16, section 11

## Context

The player was a capsule. A rigged character arrived — a 27-bone Mixamo skeleton,
1.7 m, feet at its own origin, with an idle, a walk and a run.

Spec 16 named this gap and left it: *"The player and NPCs need the same contract
and a different vocabulary — walking has facings, a creature has none."*

## Decision

**A second runtime, `WalkerBody`, beside `CreatureBody` rather than shared with
it.** Three things differ, and each is the whole of a method:

- **A character turns.** A creature is seated and faces one way for a whole
  battle. A character has a facing that changes, and it turns towards it rather
  than snapping — a four-facing world that snapped would flick the model through
  ninety degrees inside one frame.
- **A character's legs answer to the ground.** A creature's clip is a reaction to
  an event. A character's is a function of a speed.
- **A character settles.** Two steps in a row are separated by one frame at zero
  speed, and without a grace the legs flicker between running and standing on
  every cell boundary.

Sharing a base class for the two would have meant a base with one method in it.

## The world moves at the speed the animation was authored for

**This is the load-bearing number and it is measured, not chosen.**

An in-place clip carries no root motion, so the speed it implies cannot be read
off it directly: the foot's travel relative to the body is a *compressed* stride,
which every in-place clip has. What is honest is the **cadence** — how often a
foot lands. From a cadence and a step length proportional to height (about 0.75
of it running), a speed follows.

`Running` is 0.708 s per cycle: 169 steps a minute, which with this character's
1.28 m running step is **3.6 m/s**. So the world moves at 3.6 m/s and the clip
plays at a rate of one.

`tools/characters/measure_gaits.gd` prints those numbers, and exists so they can
be checked rather than believed.

The capsule crossed two metres in 0.16 s — 45 km/h. No animation of a person can
be played fast enough to match that, so the pace was never a taste question: it
was a placeholder nobody had had a reason to correct.

## How long a cell takes is derived, not declared

`cell width / ground speed`, with the width read from the map's own grid. A map
painted on a finer grid is therefore crossed at the same *speed* rather than at
the same *rate*, which is what keeps the legs matching the ground on every map
rather than on the one a number was tuned against.

## Options rejected

**Speeding the animation up to match the old pace.** A rate of 2.5, which is 430
steps a minute. Rejected because cadence is what the eye judges: correct footfall
at an impossible cadence reads as a cartoon, and no reviewer would call it
finished.

**Slowing the animation down and scaling the character up** so a 2 m cell is one
stride. Rejected because it makes the character a giant on maps authored around
human-sized props.

**One runtime for creatures and characters.** Rejected above: the shared part is
"instance a model and play a clip", which is four lines, and the differences are
everything else.

**Looping the clips in code.** Mutates an imported resource shared by every
instance. The loop is set in the `.import` instead — the pipeline is where a fact
about an asset belongs, and a runtime that patched it would be repairing the same
thing on every load.

## Consequences

**The feet slide by about 39% of a step at a run**, measured. That is the residual
after cadence is made correct, and it is the trade every game without root motion
makes. The remedy is not a constant: it is a clip authored with root motion at
the game's speed, and it is worth naming so nobody looks for a number to fix it
with.

**A gait is chosen by nearest authored speed**, not by a threshold. A threshold is
a number somebody has to pick again every time a clip is added; nearest is the
same rule however many gaits there are. It is also why `Walking` is reachable
without anything being written for it — set the ground speed to 1.5 m/s and the
character walks.

**The playback rate is clamped to a band.** Outside it a cadence stops reading as
a gait, so the band is where the error is allowed to be a sliding foot rather
than an impossible one.

**The character is not scaled.** 1.7 m with its feet at the origin is a person on
a two-metre grid; resizing would be inventing a scale the artist already chose.
Creatures *are* scaled, to the height their manifest declares, and the difference
is that a creature's size is a design fact and a person's is not.
