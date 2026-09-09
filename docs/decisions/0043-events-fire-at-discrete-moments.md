# 0043 — Events fire at discrete moments only

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 15, section 4

## Context

Grid movement gives a moment a beginning and an end (decision 0038). The
encounter check was the first thing that bought; events are the second.

The alternative is a watcher: something that observes flags and fires an event
the instant a condition becomes true.

## Decision

**Three moments, and nothing else**: interacting with the faced cell, stepping
onto a cell, entering a map.

Nothing polls, and nothing waits on a flag.

## Options rejected

**A continuous watcher.** More expressive, and it buys the reactive moment a
player notices — a door that opens the instant the key enters the bag.

Rejected on what else it makes possible. An event that can fire at any moment can
fire *during another event*, and the atomic commit of decision 0044 has no
meaning if a second event can interleave with the first. Reactivity would have to
be bought back with a lock, at which point the moments are discrete again, only
implicitly and in more code.

Polling also has no natural rate. Every frame is wasteful and every other choice
is a constant nobody can defend — the same objection that made free movement's
"a step is a distance" unacceptable in decision 0038.

## Consequences

**A door cannot open at the instant the key is obtained.** It opens the next time
the player touches it or re-enters the map. This is a real design constraint on
how quests are written, and it is named here so that nobody reads it later as a
bug to be fixed with a watcher.

Events and encounters now hang off the same three moments, which means one place
decides what a step does rather than two systems each polling in their own way.
