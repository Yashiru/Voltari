# 0053 — A defeat goes to the nearest rest point

**Status:** Accepted
**Date:** 2026-09-10
**Recorded in:** spec 14, section 9

## Context

The world could start a battle, hand the result back and save it. It could not
end a lost one. The sandbox printed a line and left the player standing where
they fell with a fainted party — and since nothing in the game heals, that is a
state a playthrough never comes out of.

Two questions had to be answered together: **where the player goes**, and **what
happens to the party**.

## Decision

**The nearest rest point, and the party restored to full health.**

A rest point is a node on a map, beside warps and zones: a cell and a facing.

"Nearest" is defined, not left to the implementation — between two maps there is
no obvious metric, so the one used is written down:

1. On the current map, fewest steps, Manhattan.
2. Otherwise fewest map transitions, walking the warp graph outward.

Fewest doors beats fewest steps, with no exchange rate between the two.

The validator refuses a world with no rest point anywhere, and any map that can
reach none.

## Options rejected

**The last rest point visited**, which is what the reference games do. It is the
familiar answer and it is a genuinely different decision. Rejected for now on two
counts: it needs a field in the save, so it is a save-format change made before
anything is authored; and it makes two players standing in the same place wake up
in different towns, which turns "where does a defeat send me" into a question
only a playthrough's history can answer. Nothing here forecloses it — adding the
memory later changes which rest point is chosen and none of the machinery around
it.

**Summing steps and transitions into one number.** Would make the metric a single
comparison. Rejected because it needs an exchange rate between a step and a door,
and any value for it is arbitrary in a way "one door beats two" is not.

**Straight-line distance.** Cheaper and wrong: movement is four-directional, so a
diagonal costs two, and a straight line calls a wall a shortcut.

**Leaving the player where they fell.** No teleport, no metric, no node type.
Rejected because it is the state that cannot be recovered from — it is the
problem, not a resolution of it.

**Ending the run.** Coherent, and a design choice nobody made. Not this game's.

## Consequences

**Healing is a placeholder, and spec 14 says so in the spec rather than in a
comment.** It is there because nothing else can heal. The day an item or a
service exists, this is the sentence to revisit — and it will be found, because
it is written where the behaviour is specified.

**A map is content that can now be wrong in a new way**, and the validator is
where that is caught: an island reachable through a door that no defeat can
recover from is invisible until somebody loses on it.

**The metric can return nothing**, and the caller handles it rather than
asserting. The validator refuses such content, so a null answer means a world
built by hand in a test — and standing back up where you fell beats a crash.

**A defeat costs nothing but the walk back.** No money, no experience, no items.
That is not a decision this entry makes; it is the absence of one, and it is what
a penalty would be added to.
