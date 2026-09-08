# 10 — Progression and the post-battle pipeline

**Status:** Draft
**Depends on:** specs 03, 07, 09; decisions 0010, 0025
**Not covered by the oracle** — see spec 02, section 3

How a creature is born at a level, and what happens to it after a battle it
survived: experience, levels, moves, evolution.

The simulation core knows none of this. It receives creatures already
constituted and hands back a finished battle; everything here happens on either
side of that.

---

## 1. Where progression lives

**L1, with the same purity constraints as the core** (`docs/architecture/layers.md`).
No engine types, no I/O, no drawn numbers. The reasons are the ones that put
them on the core: a rule that cannot be tested in isolation is a rule nobody
verifies, and progression is where a silent arithmetic slip costs a player their
save rather than a turn.

The core gains one thing: a **species type**, as data. A creature can then
reference what it is during a battle, which real mechanics need, rather than
being a bag of numbers that has forgotten where it came from.

## 2. Birth: a creature at a level

Given a species, a level, and the values that are drawn rather than derived, L1
produces a creature the core will accept.

| Source | What |
|--------|------|
| **Derived** | Stats, from base stats, IVs, EVs, level and nature (spec 08) |
| **Read** | Types, from the species (spec 09) |
| **Selected** | Moves — the last four learnable at or below that level |
| **Drawn** | IVs, nature, gender |

Nothing here is guessed at the point of use: a creature that exists has every
field decided, because a half-built creature reaching the core would be a defect
the core has no way to describe.

## 3. Drawn values, and who draws them

The core never draws; it asks named questions and something else answers
(decision 0010). That pattern applies again here, unchanged — **but through a
second interface, not by widening the first.**

`VltDecider` is the battle vocabulary, and one of its implementations is the
policy shared with the oracle (spec 02). Adding `individual_value` to it would
oblige the differential's scripted decider to answer questions the oracle never
asks, in the one class whose entire job is to encode what both engines agree on.
Diluting it costs more than a second interface does.

The two are **disjoint by construction**: no question appears in both
vocabularies, and a meta-test asserts it. That is what keeps this one pattern
applied twice rather than two ways of doing one thing — the distinction the
standards care about is same-job, not same-shape.

One seeded generator may back both. The interfaces are separate; the source of
randomness need not be.

**Rejected: passing the values in as parameters.** L1 would stay purely
functional and trivially testable. But the drawing does not disappear, it just
stops being anybody's declared responsibility — and an undeclared draw is done
with whatever RNG is nearest, which is the failure the purity rule exists to
prevent.

## 4. Experience, and who earns it

Experience is awarded **when an opponent faints**, split among the creatures
that took part and did not faint themselves.

**Participation is read from the battle log, not tracked in the state.** The log
already records every switch-in and every faint, and invariant 8 guarantees it is
complete — a state change that does not appear there is already a defect
(spec 07). Adding a participation set to the state would mean one more thing to
serialise, clone, replay and emit events for, to recover what is already
recorded.

The cost is honest: participation becomes a reading of the log, so it depends on
the log staying complete. That is a property the suite already enforces, which
is precisely why it can be relied on here.

## 5. The post-battle pipeline

The battle ends. Then, in order:

1. Experience is awarded per faint, from the log.
2. Levels rise, as far as the accumulated experience carries them.
3. Stats are re-derived at the new level.
4. Moves learnable at the levels passed are offered.
5. Evolutions whose trigger is now satisfied are applied.

The order is not arbitrary. A move learned at level 15 must be offered when the
creature passes 15, even if it ended the battle at 18 — so the pipeline works
through the levels gained, not from the final one. Evolution comes last because
it changes the species, and everything above reads the species.

## 6. Levels rise after the battle, not during it

Gen 4 applies a level-up at the moment of the faint: stats change mid-battle,
and a creature can win a fight it would have lost.

**Voltari batches them.** A creature that would have levelled mid-battle
benefits only once the battle is over.

The frontier is what is bought. Awarding experience during a turn means the core
emitting events for changes L1 causes, and progression reaching into the
resolution order — the coupling specs 04 and 06 were shaped to avoid. Keeping
the core ignorant of experience keeps that boundary a boundary.

**This is not an entry in `docs/gen4-deviations.md`.** That file records
divergences from the *oracle*, and each entry owes a test against the diverging
oracle vector. The oracle covers battle mechanics only: it has no experience, no
levels, and nothing to diverge from. Filing it there would put an entry in a
register that cannot hold it. Decision 0028 records it instead.

## 7. Learning moves, and the four-move limit

A creature holds four moves. When it learns a fifth, something must go, and
**the choice is not L1's to make**: it returns a request, exactly as a battle
returns a request for a replacement (decision 0012). The same shape, for the
same reason — a rules layer that decided for the player would be making a
decision it has no standing to make, and one that cannot be replayed.

## 8. Evolution

An evolution is a trigger plus its parameters (spec 09). The trigger id names
code, never a condition written in the content — the rule of spec 06 §8 governs
here too.

Evolving replaces the species and re-derives stats. It does not reset experience,
IVs, EVs or the moveset: the creature is the same individual wearing a different
species.

## 9. Fidelity without an oracle

Spec 02 limits the oracle to battle mechanics, so nothing here can be
differentially tested. What replaces it:

- **Published formulas**, transcribed once into code with the source recorded
  next to them.
- **Hand-derived vectors**, computed independently of the implementation. A
  vector produced by running the code proves only that the code is deterministic.
- **Property tests**, which reach where vectors do not: experience never
  decreases, a level never exceeds the cap, EVs never exceed their budget, and a
  creature born twice from the same answers is the same creature.

This is a weaker pillar than the differential and is knowingly accepted. Saying
so is the point: the strength of a test is not uniform across the project, and
pretending otherwise is how the weak parts get trusted like the strong ones.

## 10. Testing obligations

- Every drawn value goes through the L1 interface; a meta-test asserts the two
  vocabularies stay disjoint.
- Birth is reproducible: the same species, level and answers give the same
  creature, field for field.
- The pipeline is ordered: a test drives a creature through several levels at
  once and asserts the moves of every level passed are offered, not just the last.
- Every published formula has at least one vector derived by hand.

## Open points

- **The experience formula's participation rules** — whether a creature that
  switched out still counts, and how a shared award rounds. Settled with the
  formula, in the entry that records its source.
- **Experience-sharing items** have no schema until items do (spec 09).
- **Evolution triggers beyond level** — item, trade, friendship — are content the
  schema can already express; each needs the code its trigger id names.
