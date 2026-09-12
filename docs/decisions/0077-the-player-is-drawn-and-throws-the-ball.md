# 0077 — The player is drawn in battle, and throws the ball

**Status:** Accepted
**Date:** 2026-09-12
**Recorded in:** spec 17, section 2

## Context

A capture was a menu press and a log. The ball appeared out of nothing, shook,
and either held or did not. The one command in the game the player carries out
themselves rather than asking a creature to had nobody carrying it out.

A throw clip arrived with the rest (decision 0074) and had nowhere to be played.

## Decision

**The player stands on the field for the whole battle, and throws the ball.**

**Where they stand is derived**, like everything else in `BattleStaging`: beside
their own creature and off the shoulder the camera is *not* on. Both halves of
that were found by looking.

- *Behind* their creature is where a trainer belongs and where they cannot go.
  The camera watches over that creature's shoulder, so anything put behind it is
  put in front of the lens — at a metre the trainer filled a third of the frame.
- Pushing them back far enough to clear the camera makes the scene three times
  wider than the pair, and the camera pulls out until both creatures are
  thumbnails.

Beside, at about a creature's height, is where a person fits.

**The frame holds them.** The centre of what is drawn and the radius around it
both take whoever is standing there. Passing a height of zero leaves them out,
which is what a stage with nobody on it wants — and is why every existing caller
of `centre`, `framing_radius` and `eye` is unchanged.

**The throw is played when the command is taken, and returns when the ball leaves
the hand** — 0.77 s into a 3.30 s clip, measured as the moment the throwing hand
is fastest. The rest is a follow-through and a step back, and the shakes play
over it. Waiting for the clip would put two and a half seconds between the arm
coming down and anything happening.

It is claimed under the screen's own busy flag, so a second press during a throw
is the same nothing a second press during a turn is.

## Options rejected

**Playing it from the log**, as a cue in `BattleClips` beside the creature
clips. That is where everything else a battle shows comes from, and it is the
first thing to reach for.

Rejected on ordering and on coverage. The earliest capture event is the first
shake, which is the ball already in the air — the throw would play after the
thing it causes. And a throw that fails its first check emits no shake at all, so
the only event left is the result, by which time it is over.

The rule the log carries (decision 0049) is about what the player is *told* of a
battle, and it is unchanged: this is the player's own arm, started by the
player's own button, and it reveals nothing the log was filtering.

**Drawing the trainer only while throwing.** Cheaper on the frame, and it reads
as a glitch: somebody appears for three seconds and vanishes.

**Widening the frame only during a throw.** A camera that pulls back for three
seconds and returns is a camera move nobody asked for, in a screen that has no
camera direction at all.

## Consequences

**The creatures are drawn smaller.** The scene is wider than the pair now, and
the camera holds all of it. That is the price of a third body on the field and it
is paid in every battle, not only in the ones with a throw.

`game/scenes/battle/` is rough on purpose and says so — "nothing here is a camera
direction, and its replacement should be a deletion". Tuning the composition past
this belongs to whatever replaces it.

**A stage with no trainer still spends the beat.** A screen built before the
model existed, and every stage a test builds, pauses for a step and carries on —
so the pacing is the same whether or not anybody is drawn.

**The trainer is advanced by the screen.** It is the one body there that keeps
its own time: a creature plays a clip and stops, and a person breathes.
