# 0035 — The AI estimates with the engine's own damage code

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 12, section 5

## Context

To choose a move the AI must estimate what it would do. Damage is already
implemented, once, in the core.

## Decision

The AI calls **`VltDamage.compute`**, with a scripted decider: average roll, no
critical. The estimate cannot drift from the real calculation because it is the
real calculation.

**Assembling the damage input moves to one place.** Offence, defence and the
contributed modifiers are currently put together inside the turn machine; the AI
needs exactly that assembly, and it is shared rather than copied.

## Options rejected

**A "what would this move do" query on the core.** The AI would assemble nothing
and the core would keep the construction to itself. Rejected because the core
would gain a public function whose only caller sits in a layer above it — a layer
paying for someone else's convenience, and the beginning of the core knowing who
is asking.

**An approximation of its own**, cruder and faster, owned by the AI. It would
need nothing from the core at all. Rejected outright: two implementations of one
calculation is the duplication the standards forbid, and this pair would diverge
the first time an effect changed a damage stage — silently, because the estimate
has nothing to compare itself against.

## Amended when implemented: the assembly cannot move

The decision above said the input assembly would be shared. It cannot be, and
writing the view showed why: the engine assembles from a **creature**, and the AI
assembles from an **estimate** of one, built from public species data. They have
different inputs, so there is no single assembly for them to share.

What is genuinely shared is smaller and still worth extracting: **which stat a
category attacks with, and which defends against it**. That rule now lives once,
on `VltDamage`, and both sides read it. The numbers are each caller's own; the
rule is not.

`VltDamage.compute` itself is shared as decided, which was always the part that
mattered — the pipeline, not the paperwork before it.

## Consequences

**A test asserts the two paths never forked**: a move the AI predicted, then
actually played with the same decider, deals what it predicted. Without it,
sharing the code is an intention rather than a fact — the assembly could still
be handed different arguments on each side.

The AI must know the shape of what the engine assembles. That is the price of
not adding a query, and it is visible: the AI names the same pieces the engine
names, in the same call.
