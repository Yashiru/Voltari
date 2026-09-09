# 0037 — Saves are read tolerantly, one reader per section

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 13, sections 2 and 3

## Context

A save written by an older build has to keep working. The two ways to do that are
a chain of version-to-version migrations, or one reader that tolerates what is
missing.

## Decision

**One reader per section**, tolerating absent fields and supplying defaults. No
migration chain.

**Each system declares the section it persists** — a key, a version, and the pair
of functions that write and read it. Nothing enters a save by accident.

## Where tolerance stops, and what covers the rest

Tolerance handles the common change: a version adds a field and older saves do
not have it.

It does **not** handle a field whose meaning changed, or one that was renamed. A
default cannot help there — the value is present, it reads without error, and it
plays wrong, which is the worst failure a save system has. The **section
version** is what covers that: the reader branches on it, and a change of meaning
is a change of version.

From which the rule that keeps this honest: **never reuse a field name for a
different meaning.** Add a new one and leave the old alone. A tolerant reader
makes that cheap; ignoring it makes tolerance a trap.

## Options rejected

**Chained migrations**, one function per version step. Each is small, testable
alone, and the history of the format becomes readable in the code. Rejected as
more machinery than the common case needs: most changes are an added field, which
a default handles without a step, and the chain would fill with trivial links
that still have to be maintained and run.

**Snapshotting the whole world**, as the core already does for a battle. Nothing
could be forgotten. Rejected because the save would then take the shape of every
system's internals, and a refactor nobody thought of as risky would break every
existing file. There is also no unified world state today; one would have to be
invented to serialise.

## Consequences

**Forgetting to declare a section is silent data loss.** The game runs perfectly
and the player loses their inventory. That is the real cost of opting in, and it
is answered by making the round-trip test part of declaring a section, with a
meta-test that fails when a declared section has no test.

Committed fixtures of older saves are the only evidence that yesterday's files
still load. Without them, tolerance is an intention: the reader compiles either
way.
