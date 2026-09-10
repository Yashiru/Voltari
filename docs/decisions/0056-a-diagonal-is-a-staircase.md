# 0056 — A diagonal is a staircase

**Status:** Accepted
**Date:** 2026-09-10
**Refines:** decision 0051 (the stick is quantised before the world)
**Recorded in:** spec 18, section 2

## Context

Holding two arrows walked in one direction. The switch margin of decision 0051
made whichever axis was already in use hard to unseat, so the first key pressed
won and kept winning — correct by that decision, and not what a player pressing
up and right expects.

Spec 14 section 2 is unambiguous about the grid: *there are no diagonals because
there are no diagonal steps*. Nothing about that has changed, and the reasons
have not either — a diagonal step would need a rule for cutting the corner
between two walls, a facing vocabulary of eight values that warps, events and
rest points already store as four, and its own encounter check.

## Decision

**Two axes pushed hard enough alternate, one cell at a time, with no pause.**

East, north, east, north — every one of them an ordinary step. Walkability,
warps, events and encounter checks all happen exactly as they always did, twice,
because two cells really were crossed. What is new is only that the walk does not
stall between them, so the eye reads a staircase as a diagonal.

**"Hard enough" is a floor on both axes**, not the ratio between them. Two keys
held clear it; a thumb parked on the diagonal clears it; a tremor on the second
axis does not.

**The alternation advances per step, not per frame.** The quantiser says what is
wanted every frame and only the caller knows which of those became a step,
because only the caller holds the cooldown. `Held.stepped` is that door.

## What this does to decision 0051

The switch margin now governs the band **below** the diagonal floor, and that is
where it always meant to work. Its stated reason is a stick near 45 degrees
flipping axis *on a tremor*: a tremor is a small second axis, and a small second
axis is exactly what stays under the floor. Above it, both axes are deliberate
and there is nothing to protect the player from.

No number in 0051 changed. What changed is the range it applies over.

## Options rejected

**Real diagonal steps.** Eight directions, one step per press. Rejected on the
price listed in the context — it is a change to spec 14's grid, not to how a
stick is read, and every layer that stores a facing pays for it.

**Alternating without the floor**, on any two axes at all. Rejected because it is
decision 0051 undone: an analog stick near a straight push has a small second
axis at all times, and the zigzag that margin exists to prevent would be back for
every player using a thumbstick.

**Letting the caller ask for a diagonal.** A flag on `of()`, set by whatever knows
it is a keyboard. Rejected because it is the split decision 0051 refused: this
class reads a vector and knows nothing about fingers, keys or devices, and a
keyboard and a phone that took different paths through it would drift.

## Consequences

**A diagonal costs two encounter checks**, because two cells were crossed. That is
the honest answer and it is not a bug: a player who walks a staircase through
long grass has taken two steps in it.

**Which axis goes first is whichever was not used last**, so a walk that changes
from straight to diagonal continues on the other axis rather than repeating.
Nothing depends on that; it is stated because it is the only visible arbitrary
choice here.

**The first step of a diagonal from rest still turns before it walks**, like any
other push into a new direction. Only the steps after it chain.
