# 0013 — The core validates commands and rejects illegal ones

**Status:** Accepted
**Date:** 2026-09-07

## Context

Commands reach the core from the UI, from the AI, and eventually from the
network. Something has to decide what happens when a command is not legal:
switching to a fainted creature, naming an unknown move, targeting an empty slot.

## Decision

The core validates and returns an explicit error. It never produces a corrupted
state, and never silently substitutes a different action.

**Legality is distinct from game rules.** Running out of PP yields Struggle —
that is a rule resolved during execution, not a rejected command. Validation
answers only whether the command was well-formed and permitted when submitted.

## Options rejected

- **Assume input is valid, validate in the UI.** Less code in the core and
  faster. But the fuzzer could no longer explore malformed input — a crash and a
  refusal would be indistinguishable — and PvP would need the same rules
  reimplemented at the network boundary, giving two implementations of one rule.
- **Validate and auto-substitute.** Merges error handling with game rules, so a
  bug in the caller silently becomes a legal-looking move.

## Consequences

The rules of legality live in exactly one place, which the UI, the AI and the
network layer all inherit.

Whether the core should additionally *expose* the list of legal commands per slot
is left open. It would remove the last reason for the UI and the AI to re-derive
the rules, at the cost of more API surface to specify and test. Not decided here.
