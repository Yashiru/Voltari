# 14 — Overworld and encounters

**Status:** Draft
**Depends on:** specs 09, 10, 13; decisions 0004, 0010, 0029

This is the first specification above L1, and the first where the engine stops
being pure computation. Everything written so far touches neither the engine nor
a file. A map does both.

So most of this document is about **where that line falls**, and what is bought
and given up on each side of it.

---

## 1. The line

**The map is ordinary Godot.** Tiles, a character body, area triggers. Movement,
collision, warp traversal and zone detection are the engine's own work, and the
world state lives in the scene tree rather than in a pure structure beside it.

That is a departure from every layer below, taken deliberately. Rewriting tile
collision in pure GDScript is not hard — but the testability it buys is worth
little here, because **the world carries no formula anyone could get subtly
wrong**. A warp either arrives somewhere or it does not, and that is visible the
first time it is walked. Damage is not like that; a stat calculation off by one
plays for months without being noticed. The purity discipline exists for the
second kind of code, and the overworld is the first.

**What stays pure is the part that carries numbers.** Whether an encounter
happens, which slot of the table is drawn, and at what level. Those are rules
with a distribution — the exact thing that is wrong quietly rather than
obviously. They live in L1 with the other out-of-battle rules, under the purity
lint, and are tested normally (section 9).

**The cost, stated plainly:** the world state is not covered by tests. A broken
warp, a zone that never fires, a collision gap — all of these are found by
playing. Two things narrow that gap without closing it: the build validates every
cross-reference a scene cannot guarantee (section 7), and the numeric half is
tested like the rest of the engine.

## 2. Movement is locked to the grid

The player moves one cell at a time. Rendering interpolates between cells and the
3D characters animate through the step (decision 0020), so it looks continuous;
the logic is discrete.

This is not only an implementation choice. It gives **a step a definition**. An
encounter check happens per step, and with grid movement a step is an event with
a beginning and an end. Under free movement it would become a distance
threshold — a constant with no defensible value, tuned until it felt right and
then never touched again.

Facing is part of position, not a rendering detail: what a warp does, what a zone
sees, and what spec 15 will interact with all read it.

## 3. Maps are painted, not written

A map is a Godot scene. Tiles carry the collision. Warps and encounter zones are
nodes placed on it.

**The cost this pays is real and worth naming:** a scene diff is unreadable, and
decision 0004 made diff readability a first-order criterion. That criterion is
suspended for this one class of file.

The reason it can be is what review actually buys in each case. A species file
reviews well because its meaning *is* its text — a base stat of 130 is wrong on
the page. A tile grid's meaning is visual, and no reviewer has ever caught a
level-design mistake by reading coordinates. Against that, authoring a grid by
hand in text is not a workflow anybody would keep.

What review would have caught is instead caught by the build: the parts of a map
that are **not** geometric — which table a zone names, where a warp leads — are
checked mechanically rather than by eye (section 7).

## 4. Encounter tables are content

`content/encounters/<id>.yaml`, one table per file, the filename being the
identifier (spec 09, sections 2 and 3). A zone names a table id, so a table used
by three maps exists once and is balanced in one place.

| Field | Meaning | Validated |
|-------|---------|-----------|
| `rate` | Chance of an encounter per step, in 256ths | 1–255 |
| `slots` | The table proper, at least one entry | Non-empty |
| `slots[].species` | What is met | Species exists |
| `slots[].levels` | `{min, max}`, inclusive | 1 ≤ min ≤ max ≤ 100 |
| `slots[].weight` | Relative frequency | Positive |

The rate belongs to the table rather than to the zone. A zone is a shape on a
map; how dangerous that terrain is belongs with what lives in it, and putting the
rate on the zone would mean the same table felt different on every map for no
authored reason.

Weights are relative, not percentages. Percentages must sum to 100, which turns
adding a creature to a table into an edit of every other line — the change most
likely to be made, made as expensive as possible.

## 5. How an encounter resolves

Per step inside a zone, three questions, then the chain that already exists:

1. **Does an encounter happen** — against the table's rate.
2. **Which slot** — proportional to the weights.
3. **Which level** — within the slot's range, inclusive at both ends.

Then spec 10's birth: `VltBirth.at_level` produces the creature, with its IVs,
nature and gender drawn through the generation vocabulary. The world produces a
species and a level and stops there; it does not assemble a battle.

No oracle covers any of this (spec 02). The evidence is hand-derived vectors plus
the distribution itself, which is the part that matters: over many draws, slots
must appear in proportion to their weights, and a slot with twice the weight of
another must be drawn about twice as often. A subtly wrong selection is
indistinguishable from luck in any single draw.

## 6. Encounter decisions are a fourth vocabulary

`VltEncounterDecider`, asking `encounter_occurs`, `encounter_slot` and
`encounter_level`. Same pattern as decisions 0010 and 0029, and the vocabularies
stay disjoint by construction — no question appears in two, and the existing
meta-test is extended to cover the new pairs.

It is not folded into the generation vocabulary because it has a **different
caller at a different moment**. The world asks where and when; birth asks with
what. They run one after the other, which is exactly the situation where merging
two vocabularies looks harmless and later makes each of them answerable in a
context it was never written for.

One seeded generator may still back all four. Separate vocabularies do not
require separate sources of randomness (decision 0029).

## 7. The build validates maps; it does not export them

The scene is the truth at runtime, so **there is nothing to export**. Writing the
grid out to a payload would only mean rebuilding a tile map from JSON on load, at
which point the same information lives in two places and can drift.

What the build does instead is the cross-reference check of spec 09 section 8 —
the typos that survive review and produce content that looks right and plays
wrong:

- a warp naming a map that does not exist
- a warp whose destination cell does not exist, or is not standable
- a zone naming an unknown encounter table
- a zone with no table at all
- a map with no way in

It reports **all** problems and then exits, like the content build. A map pass
fixes ten broken warps in one go or ten times over.

This is the only mechanical guard the overworld has, which is why it validates
what a scene genuinely cannot: a warp's destination lives in a *different* file
from the warp.

## 8. The world reaches the save through its own section

Spec 13 requires each system to declare its part of the save. The world's part is
held by the engine rather than by a pure structure, so something has to convert
one into the other.

That converter is **a save section that lives with the world**, not in `save/`. A
section that reads a character body cannot sit under the purity lint, and moving
it there would either break the lint or force the world back into a pure model
section 1 rejected. `VltSaveSection` is pure and L3 depends on it: the dependency
runs downward, so this is not an inversion.

It carries the map id, the cell and the facing. Quest flags belong to spec 15 and
will declare their own section — which is the mechanism working as intended.

**One direction only.** The section reads the world and produces dictionaries;
the world never reads a file, and L5 still owns the bytes (spec 13, section 1).

The identifier rule bites here for the first time outside content: **a map id is
held in a save**, so it is stable, `snake_case`, and never reused for a different
map. Renaming a map file is a migration, not a rename.

## 9. Testing obligations

- **Slot selection matches the weights.** Over many draws, proportions hold. This
  is the property that a wrong implementation passes every individual test.
- **A level lands inside its slot's range**, both ends inclusive, across the
  degenerate case where `min == max`.
- **The rate check is monotone**: a higher rate never produces fewer encounters.
- **Determinism at a fixed seed** — the same seed gives the same encounter.
- **The four vocabularies stay disjoint**, by extending the existing meta-test.
- **Every authored table loads** into its typed form (spec 09, section 10).
- **The build rejects a broken map**, proven by fixture maps built to fail: an
  unknown table, a warp to nowhere. A validator with no failing fixture is a
  validator nobody has seen fail.
- **The world's save section round-trips** — part of declaring a section, not an
  extra (spec 13, section 8).

**What is not tested, stated here rather than left to be discovered:** movement,
collision, warp traversal and zone detection. Section 1 explains why, and this
line exists so that nobody later reads the absence as an oversight.

## Open points

- **Time of day.** `layers.md` places it in L3. A zone naming one table cannot
  vary by hour; the extension is to let it name several, keyed by a condition.
  Adding a key is not a breaking change — the same argument spec 09 makes for
  learnset methods — so nothing here forecloses it.
- **Encounter modifiers**: repellents, a quiet period after a battle, a lead
  creature that influences what appears. All of them modify the rate, which is
  part of why the rate is a value read from the table rather than a constant in
  the code.
- **Other encounter triggers**: water, fishing, fixed encounters. The table shape
  is the same; what differs is what starts the check. Unspecified.
- **Map size and loading.** One scene per map, loaded whole. Whether a large
  region needs anything more is a performance question, and performance is
  measured, not asserted.
- **NPCs, dialogue, interaction and flags** — spec 15, which is what will make a
  map more than terrain.
