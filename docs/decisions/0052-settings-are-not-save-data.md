# 0052 — Settings are not save data

**Status:** Accepted
**Date:** 2026-09-10
**Refines:** decision 0040 (a section belongs to its system)
**Recorded in:** spec 18, sections 3 and 4

## Context

Spec 13 built a save format where each system declares a section, and two
systems already use it. Key bindings, volume, language and text speed are
persistent state and would fit a section without any work.

## Decision

**Their own file, beside the saves and not inside one.** The same writing
mechanism — temporary file, then replace — because the failure to avoid is
identical.

**Backgrounding saves the game when it safely can.** Not mid-battle (spec 13,
section 6), not mid-event (decision 0044), and otherwise yes.

## Why settings are not a section

They are not the player's progress, and every property of a save is wrong for
them:

- They **outlive a save**. Deleting a playthrough must not reconfigure somebody's
  controls.
- They are **shared by every save**. In a section, two playthroughs would each
  carry their own copy and the second one to be played would win.
- They are **read before a save is chosen**. Language decides what the menu that
  picks a save is written in.

## Options rejected

**A section of the save.** One file, one mechanism, already built. Rejected on
the three properties above — the mechanism fits and the meaning does not, which
is the most expensive kind of near-miss.

**Never saving automatically on background.** No surprise, no unintended
overwrite. Rejected because on a phone the application is killed constantly, and
a session lost to a phone call is a session the player did nothing to lose.

**Always saving on background, suspending whatever blocks it.** Nothing is ever
lost. Rejected because it reverses spec 13 section 6 and decision 0044, whose
reasons have not changed: battle state is the most-changed part of the engine and
does not belong in a file that must be read for years.

## Consequences

**Two files with the same writing discipline**, and no second mechanism: the
class that writes bytes is the one spec 13 already has.

**A settings file that will not parse starts the game on defaults**, rather than
not starting. The asymmetry with a save is deliberate — a save that cannot be
read is the player's history and is worth interrupting them for; a volume slider
is not.

**The automatic save is the ordinary one.** Being interrupted by the very thing
that prompted the write is exactly the case the temporary-file dance exists for,
so nothing new is needed to make it safe.
