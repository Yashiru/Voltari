# 0051 — The stick is quantised before the world sees it

**Status:** Accepted
**Date:** 2026-09-10
**Recorded in:** spec 18, sections 1 and 2

## Context

Decision 0038 locked movement to the grid, and the encounter check depends on
it: grid movement is what gives **a step** a beginning and an end.

The control players expect on a phone is a floating stick — touch anywhere, drag,
walk. It is continuous, and it points at 43 degrees as readily as at 45.

## Decision

**A layer between the stick and the world turns a vector into a direction.** The
world's `step(direction)` is unchanged and never learns that a stick exists.

Four rules do the turning: a dead zone, the dominant axis, a bias toward the
direction already held, and a flick that turns without walking. The numbers in
them are tuned by feel and are not structure.

The same layer serves a gamepad, which is analog too. A keyboard is that layer
handed a vector already pinned to an axis — which is what makes a phone and a
keyboard unable to drift apart: they meet before the world does.

## Options rejected

**An on-screen d-pad.** Four zones, one step each, no interpretation at all —
and this decision would not exist. Rejected by the maintainer on feel: it is the
control players find dated, and it costs screen space on the smallest screens.

**Tap a cell to walk there.** The most natural thing on a phone. Rejected on what
it needs: a path, which the world has not got, and a rule for what happens when
an encounter fires halfway along one. Both are real systems, and neither is
justified by an input method.

**Letting the world take a vector**, moving freely. Rejected because it is
decision 0038 reversed. Free movement makes a step a distance threshold — a
constant nobody can defend — and the encounter check has nothing to hang on.

## Consequences

**The bias is the part that will look like an accident.** Near 45 degrees the
dominant axis flips on a tremor, so without it a player walking north-east
zigzags one cell at a time. It is a property a test can hold and a hand cannot:
trying it once feels fine, and it is the hundredth step that reveals it.

**The overworld tests are untouched.** They drive `step(direction)` on fixture
maps with no input at all, which is only true because the quantiser stops short
of the world.

**The quantiser is a pure function**, so it is tested as one — vectors in,
directions out. It is the only part of input that has anything to be wrong about.
