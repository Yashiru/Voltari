# 0044 — An event is atomic

**Status:** Accepted
**Date:** 2026-09-09
**Refines:** decision 0036 (an unread save section is kept)
**Recorded in:** spec 15, section 5

## Context

An event sets flags as it runs. On mobile the application will be killed
mid-cutscene — spec 13 already accepts losing a battle that way.

Losing a cutscene is not the same thing. A battle is discarded whole; a cutscene
may already have written to the save.

## Decision

**An event's flags land when it finishes.** It ran or it did not. An interrupted
event replays from its start.

**The player cannot save while an event runs**, the same way they cannot save
mid-battle (spec 13, section 6).

## Options rejected

**Flags landing as they are set.** This is what the code does naturally with no
machinery at all, which is exactly why it had to be written down — it is the
outcome of not deciding.

Rejected because it leaves a save holding a quest half advanced, in a state no
event knows how to resume and no validator can recognise as wrong. The player
finds out by being unable to continue, with no way back.

**Saving mid-event, atomically.** Would preserve the cutscene across a kill.
Rejected because the save would then have to hold the event's position — which
node, which nested sequence — and that is the most-changed data in the game
sitting in a file that must be read for years. The same argument that keeps
battle state out of saves.

## Consequences

**An event must be replayable from its start**, which is a constraint on how
events are written and not only on how they run. A step that cannot simply be
repeated — consuming an item, paying money — has to land in the same commit as
the flags.

**Atomicity covers persistent state, not what is shown.** An NPC that walked
across the room mid-event is not rolled back; nothing was saved, so there is
nothing to roll back.

**An interrupted cutscene replays from the beginning**, which players will
notice and some will find tedious. Accepted: repeating a scene is an
inconvenience, and a quest stuck in an unrepresentable state is not.

This is what makes decision 0043's discreteness load-bearing rather than
stylistic. An atomic commit means nothing else may run in the middle, and only
discrete triggers guarantee that without a lock.
