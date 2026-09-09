# 0042 — Flags are booleans and named integers

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 15, section 3

## Context

Quest state has to persist, and it is the longest-lived data the game has. A
flag written today is read by every version afterwards and sits in saves nobody
can migrate.

So the shape is chosen once. The question was whether one kind is enough.

## Decision

**Two kinds, and no more.** A named boolean for "this happened". A named integer
for "where this quest stands" and "how many".

Absent reads as `false` or `0`, which is what lets an older save load a newer
build's flag: it simply is not there yet (spec 13, section 3).

**A flag id is held in a save**, so the identifier rule of spec 09 section 3
applies unchanged — `snake_case`, stable, never reused for a different meaning.

**A flag this build does not recognise is kept, not dropped.** Decision 0036's
argument, applied inside a section rather than between sections.

## Options rejected

**Booleans only.** One kind, the simplest possible save section, and it covers
most of what a game actually stores.

Rejected on what it forces everything else into. A five-step quest becomes five
booleans, and nothing stops step 4 being true while step 2 is false. That state
cannot be described, nobody will look for it, and no event knows how to resume
from it. An integer moves in one direction and cannot contradict itself.

The cost of being wrong here is asymmetric, which decided it: adding a kind later
is cheap, because a tolerant reader treats an absent flag as a default. Migrating
quests already encoded as boolean sets in players' saves is not.

**Arbitrary named values.** Nothing would ever block. Rejected because nothing
could ever be checked either — not at build time, not when reading a save, not by
the validator that has to find a flag read but never set (spec 15, section 7).

## Consequences

The validator gains a check it could not otherwise make: with two known kinds, a
flag's every read and write can be found and compared. A misspelling at one of
two sites is the failure this catches, and it is invisible to any test of a
single event.

Deleting a flag from the code does not delete it from saves. That is intended —
a build that has lost a quest must not silently erase the player's progress
through it — and it means the set of flags in the wild only ever grows.
