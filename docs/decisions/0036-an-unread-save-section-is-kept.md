# 0036 — A save section that cannot be read is kept, not dropped

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 13, sections 4 and 5

## Context

A save may hold a section this build cannot read: written by a newer version, or
belonging to a system this build does not have.

The maintainer chose to load what can be read rather than refuse the file — with
the game announcing the incomplete read and asking before continuing.

That choice has a consequence it does not state. A partly-understood save is
rewritten **complete** on the next write, and everything unread is gone. The
player finds out weeks later, by looking for something that is missing.

## Decision

**An unrecognised section is carried through verbatim** and written back
untouched.

Keeping it costs a dictionary held in memory. Dropping it costs the save.

**An incomplete read is announced, names what could not be read, and is
confirmed before the game continues.** And **the previous file is kept before
the first write over a save that read incompletely** — the confirmation buys
informed consent, the backup is what makes that consent recoverable when it was
given too quickly.

## Options rejected

**Refusing to load**, which is what spec 09 does for content. Consistent, and an
intact file could still be rescued by a later build. Rejected on whose problem it
is: content is the developer's and a save is the player's. Refusing leaves them
unable to play, which is the worst possible moment to be right.

**Loading silently and dropping the rest.** Simplest, and the player is never
interrupted. Rejected because they are never told either, and they proceed on a
save they have no reason to distrust until it is too late to do anything.

## Consequences

Sections are read independently, so one that fails cannot take another down with
it. That is a constraint on the format, not just on the reader.

A build that does not understand a section still writes it back correctly, which
means **downgrading is survivable** — playing an older build does not destroy
what a newer one wrote. That was not the aim, and it is worth having anyway.

The announcement needs wording a player can act on, which is L4's problem and
is not solved here. Naming the sections is the minimum; explaining what they
were is not something the save layer knows.
