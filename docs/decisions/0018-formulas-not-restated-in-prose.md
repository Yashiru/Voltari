# 0018 — The formulas are not restated in prose

**Status:** Accepted
**Date:** 2026-09-07

## Context

Spec 08 covers damage, stat derivation, accuracy, critical hits and speed
ordering — the arithmetic the whole fidelity claim rests on. The obvious thing to
do is write those formulas out in the specification.

## Decision

Spec 08 defines the **shape and discipline** of the formulas — staged pipeline,
integer arithmetic, extraction protocol, verification rules — and does not
contain the formulas themselves.

The truth is the code plus its oracle vectors.

## Options rejected

- **Writing the formulas out in the spec.** The natural reflex, and it reads
  well. But the formula would then exist in three places: the prose, the code and
  the vectors. The prose is the one nobody runs, so it is the one that goes stale
  — inside the document meant to settle disputes. Worse, a formula transcribed
  from memory would be an unverified assertion sitting exactly where verification
  is supposed to live.
- **Prose as the source, code derived from it.** Would make the document
  authoritative, but nothing would check that the code still matches, and the
  oracle — not us — is the authority on Gen 4 behaviour anyway.

## Consequences

Consistent with spec 03, which refuses to enumerate effects, and spec 04, which
refuses to name them: the specifications describe structure and rules, while
content lives where it can be executed and verified.

A reader wanting the actual damage formula reads the code and its vectors, not
this document. That is a real ergonomic cost, accepted because a stale formula in
the fidelity reference is worse than an absent one.

The extraction protocol becomes load-bearing: vectors are generated *before*
implementation, so nothing distinguishes a correct implementation from a
plausible one by accident.
