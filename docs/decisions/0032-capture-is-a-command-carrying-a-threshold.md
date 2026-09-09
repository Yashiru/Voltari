# 0032 — Capture is a command carrying a threshold

**Status:** Accepted
**Date:** 2026-09-09
**Refines:** decision 0029 (a second decision interface)
**Recorded in:** spec 11, sections 1 and 2

## Context

Throwing a ball takes the turn, so capture happens inside a battle. But the rule
that decides it reads a ball, a species' capture rate and the target's condition
— content the core has never known anything about.

## Decision

Capture is a **command the turn machine resolves**, and it carries a threshold
the rules layer already computed. The core receives a number, asks a named
question against it four times, and reports the shakes.

Stages 1 and 2 of the formula — the modified rate, then the shake threshold —
are L1. Stage 3, the four checks, is the core.

## Options rejected

**The core knowing what capture is**, carrying the formula and the ball data.
Everything in one place and nothing to precompute. Rejected because the core
would learn what an item is and what a capture rate is, and specs 04 and 06 are
built on the turn machine naming no effect and knowing no content. It would be
the first exception, in the layer with the strongest claim to having none.

**Resolving it outside the turn**, suspending the battle and answering in L1.
The core learns nothing at all. Rejected because throwing a ball would stop
costing the turn — the opponent would not act — which changes the game rather
than the code.

## The question goes on the battle decider

Decision 0029 kept generation questions off `VltDecider`, because that class
carries the policy shared with the oracle and must stay exactly as wide as what
both engines agree on. The shake check goes on it anyway, and the distinction is
worth stating.

0029 was about a question that is **not a battle question at all**: a creature
is born long before any battle. A shake happens mid-turn, alongside the accuracy
roll and the critical, and is answered by the same decider driving the same turn.
The oracle's silence about capture is a limit of its *scope* (spec 02 puts
capture outside it explicitly), not a sign that the question belongs elsewhere.

The rule that follows: the battle decider carries the questions a turn asks. What
the oracle happens to cover decides which of them the differential can check, not
which of them exist.

## Consequences

`VltScriptedDecider` answers a question no vector exercises. That is the cost,
and it is one method rather than a third interface for one question.

A certain capture needs no special case: the rules layer passes a threshold of
65536 against a draw of 0 to 65535, so every check passes and the core keeps one
path.
