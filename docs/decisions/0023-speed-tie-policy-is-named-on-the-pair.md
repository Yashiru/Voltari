# 0023 — The scripted speed-tie policy names a winner in the pair, not a side

**Status:** Accepted
**Date:** 2026-09-08
**Refines:** decision 0009 (differential by decision policy), decision 0010

## Context

`VltScriptedDecider` answered `speed_tie(first, second)` with
`speed_tie_winner_side`: the reference whose side matched won.

That reads fine while a tie can only be between opponents, which is true in
singles — a side never submits two commands, so the two tied references always
carry different sides. In doubles two allies can tie, both references carry the
same side, and the policy has nothing to choose on. It then returned `second`,
not because anything declared that but because that was the else branch.

Found by writing the first doubles test: the expected order failed, and the
engine turned out to be right. It asked the decider, as it should; the decider
answered arbitrarily.

## Decision

The policy names **which of the two commands put to the decider wins** —
`EARLIER` or `LATER`. Well-defined for every tie, ally or opponent.

The oracle side normalises the tied slice to the engine's canonical order (side,
then position) before applying the policy, so "earlier" means the same thing in
both engines. It then mirrors the engine's adjacent-pair walk rather than
reversing the slice: the two agree on a pair and diverge on three or more, which
a doubles vector would reach.

## Options rejected

**A second setting for ally ties**, keeping the side-named winner for opponents.
Nothing existing would have moved. Rejected as two settings for one question,
with the caller expected to know which applies — the second way to do one thing
that the standards forbid.

**Leaving it and documenting the limit.** The defect is latent: no differential
vector is a doubles battle, so nothing relies on the answer today. Rejected
because it comes due exactly when doubles vectors are written, which is when the
tooling most needs to be trustworthy.

## Consequences

The fixture policy key changes from `speed_tie_winner_side` to
`speed_tie_winner`. Regenerating the six battle vectors changed that key and
nothing else — every event stream is byte-identical, which is the evidence that
this is a renaming of the policy and not a change of behaviour.

Ties of three or more still deserve a vector once doubles enter the
differential. Both sides now implement the same walk, but nothing yet proves
they agree on it.

**Closed.** `battle/0007-doubles-tie` and `battle/0008-doubles-allies` put four
creatures on the field under the "later" policy, and the two engines agree.
Truncating the engine's tie walk to its first adjacent pair fails both and
leaves every singles vector passing, so the vectors demonstrably reach what a
pair could not.
