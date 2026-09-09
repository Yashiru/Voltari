# 0034 — The AI sees a filtered view, and it is its own type

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 12, section 2

## Context

The AI needs to read the battle to choose a command. Reading the battle state
gives it exact health, individual values, effort and the opposing bench — things
no player can see.

## Decision

The AI receives a **filtered view**: what a player on its side would perceive.
Health as a proportion, no individual values, no effort, no unrevealed moves,
nothing about the opposing bench.

**The view is a distinct type**, derived from the state and a viewpoint. Not a
`VltBattleState` with fields blanked.

## Why a separate type rather than a blanked state

A blanked state is the same type as the real one. Nothing would stop it being
handed to the engine, and nothing would stop an AI holding a real state and never
noticing which it had.

The type is what makes "the AI cannot cheat" a property the compiler enforces
instead of a discipline the reviewer checks. Spec 07 draws the same line for the
log and it has held; drawing it differently here would give the project two
answers to one question, and the leaking one would be whichever nobody was
looking at.

## Options rejected

**Reading the full state.** Nothing to build, and a strong AI comes free.
Rejected because it cheats by construction: fairness would become a discipline of
deliberately ignoring what is in hand, which nothing verifies. It is also
incompatible with the lockstep PvP the layering exists to keep possible, where
each side knows only its own.

**Full state with a declared cheating budget** — an easy AI ignores individual
values, an expert one reads them. Expressive, and difficulty could be dialled by
what the AI is allowed to know. Rejected because the rule would live in the
discipline of the code rather than in the type, and "which AI knows what" becomes
a matrix to keep true by hand.

## Consequences

**A second shape of the battle exists**, and that is a real cost. It is kept
honest by being derived rather than authored: one function from state and
viewpoint, with a test for every field it claims to hide.

That test is the load-bearing one. A view widens by convenience, one field at a
time, and each widening looks reasonable on its own.

**The bench is hidden from the AI about its opponent — and this spec did not
answer what it may know about its own side.** An AI that never switches is weak,
and switching needs to see the bench. Recorded as open rather than decided by
accident.
