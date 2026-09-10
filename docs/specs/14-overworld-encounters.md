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

**The map is ordinary Godot.** A painted grid and nodes placed on it. Movement,
collision, warp traversal and zone detection are the engine's own work, and the
world state lives in the scene tree rather than in a pure structure beside it.

No physics body: grid movement is a cell lookup, and a character body would be
a simulation running underneath a decision that was already made discretely.

That is a departure from every layer below, taken deliberately. Rewriting tile
collision in pure GDScript is not hard — but what purity would buy here is worth
little, because **the world carries no formula anyone could get subtly wrong**. A
warp either arrives somewhere or it does not. Damage is not like that; a stat
calculation off by one plays for months without being noticed. Purity is what
lets fuzzing and mutation testing loose on the second kind of code, and the
overworld is the first: examples are enough to pin behaviour that is either right
or visibly wrong.

**What stays pure is the part that carries numbers.** Whether an encounter
happens, which slot of the table is drawn, and at what level. Those are rules
with a distribution — the exact thing that is wrong quietly rather than
obviously. They live in L1 with the other out-of-battle rules, under the purity
lint, and are tested normally (section 9).

**The cost is a weaker kind of test, not the absence of tests.** The world's
behaviour is covered — on fixture maps, without rendering (section 9). What it
gives up is the *quality* of coverage the rest of the engine has. Spec 05 rests
on three pillars: a differential against the oracle, invariants under fuzzing,
and mutation testing. None of the three reaches a scene tree. Fuzzing a world
means driving a node graph, and mutating it means rebuilding that graph per
mutant, which is what makes the core's mutation pass affordable and the world's
not.

So the world gets example-based tests: real, and the weakest pillar the project
has. That is stated here so the difference is understood as a property of where
the code lives, rather than as an effort somebody forgot to make.

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

> **How to actually build one:** `docs/authoring-maps.md`. This document settles
> what a map is; that one is the workflow.

## 3. Maps are painted, not written

A map is a Godot scene, and it carries **three painted layers**, of which only
two are rules. One says which cells exist; the second says which of them stop
you. Warps, encounter zones, events and rest points are nodes placed on top.

The third is **decoration, and nothing reads it** (decision 0054). A flower, a
crack in the ground, a border: things that must not claim a cell exists and must
not stop anybody. Without it, every decoration would have to be baked into a
terrain tile, and the tile library would carry one item per combination of ground
and ornament.

It is deliberately not exposed by the map's interface. A layer no accessor
returns is a layer no rule can come to depend on by accident — which is the only
thing keeping "merely there" from drifting into meaning something.

Nothing validates it either. Decoration painted off the edge of the map is a
mistake, and it is a *visual* one: the reviewer who would catch it is the person
looking at the map, which is section 7's whole criterion for what gets checked
mechanically and what does not.

Walkability is authored rather than inferred from the model standing on a cell,
which keeps art and rule apart: replacing a rock with a bush becomes a change of
art and not a change of what the player can do. The price is two passes of
painting that can disagree, and nothing detects a wall you can walk through.

A cell with no terrain is off the map, and off the map blocks exactly the way a
wall does. That falls out rather than being special-cased, so no map needs a
fence painted around its edge.

**The cost this pays is real and worth naming:** a scene diff is unreadable, and
decision 0004 made diff readability a first-order criterion. That criterion is
suspended for this one class of file.

The reason it can be is what review actually buys in each case. A species file
reviews well because its meaning *is* its text — a base stat of 130 is wrong on
the page. A tile grid's meaning is visual, and no reviewer has ever caught a
level-design mistake by reading coordinates. Against that, authoring a grid by
hand in text is not a workflow anybody would keep.

What review would have caught is instead caught mechanically: the parts of a map
that are **not** geometric — which table a zone names, where a warp leads — are
validated rather than read by eye (section 7).

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

## 7. Maps are validated, not exported

The scene is the truth at runtime, so **there is nothing to export**. Writing the
grid out to a payload would only mean rebuilding a tile map from JSON on load, at
which point the same information lives in two places and can drift.

What is checked instead is the cross-reference category of spec 09 section 8 —
the typos that survive review and produce content that looks right and plays
wrong:

- a warp naming a map that does not exist
- a warp whose destination cell does not exist, or is not standable
- a warp sitting on a cell nobody can stand on, so it can never fire
- a zone naming an unknown encounter table
- a zone with no table at all
- two zones claiming one cell, which has no right answer
- two maps claiming one id, which a save cannot tell apart
- a map no warp leads to
- a world with no rest point anywhere, and a map that can reach none (section 9)

**It runs engine-side, not in the content build.** Maps are scenes and only Godot
can load one, so a Node script could not read a map without reimplementing the
scene format. This is the split spec 09 section 8 already makes for effect ids,
which the build cannot see either, and the reason is the same: the check belongs
where the thing being checked can actually be read.

Reachability is the one check that needs a fact no map carries — where a new game
begins. It is skipped when that is not supplied, rather than guessed at.

It reports **all** problems rather than stopping at the first. A map pass fixes
ten broken warps in one go or ten times over.

This is the only mechanical guard the overworld has, which is why it validates
what a scene genuinely cannot: a warp's destination lives in a *different* file
from the warp.

## 8. The world reaches the save through its own section

Spec 13 requires each system to declare its part of the save. The world's part is
held by the engine rather than by a pure structure, so something has to convert
one into the other.

That converter is **a save section that lives with the world**, not in `save/`. A
section that reads a node cannot sit under the purity lint, and moving it there
would either break the lint or force the world back into a pure model section 1
rejected. `VltSaveSection` is pure and L3 depends on it: the dependency
runs downward, so this is not an inversion.

It carries the map id, the cell and the facing. Quest flags belong to spec 15 and
will declare their own section — which is the mechanism working as intended.

**One direction only.** The section reads the world and produces dictionaries;
the world never reads a file, and L5 still owns the bytes (spec 13, section 1).

The identifier rule bites here for the first time outside content: **a map id is
held in a save**, so it is stable, `snake_case`, and never reused for a different
map. Renaming a map file is a migration, not a rename.

## 9. Losing has somewhere to send you

A defeat has to end somewhere. A game that ended a lost battle by putting the
player back on the map with a fainted party would be a game that could not
continue: nothing else in it heals.

So a map carries a third kind of node beside warps and zones — a **rest point**,
a cell and a facing. Losing teleports the party to the nearest one and restores
it to full health.

**"Nearest" needs a metric, and between two maps there is no obvious one.** The
one chosen is written down rather than left to the implementation:

1. On the current map, the fewest steps away, counted as Manhattan distance —
   movement is four-directional, so a diagonal is two steps and a straight-line
   distance would call a wall a shortcut.
2. Otherwise the fewest map transitions, walking the warp graph outward from
   where the player fell. The first map reached that has one wins, and inside it
   rule 1 applies from the cell the warp arrives at.

Fewest doors beats fewest steps, and there is no exchange rate between them. A
metric that summed the two would need one, and any number picked would be
arbitrary in a way this is not.

It is **not "the last one visited"**, which is what the reference games do. That
is defensible and it is a different decision: it needs a memory in the save, and
it makes two players standing in the same place wake up somewhere different.
Decision 0053 records the choice and what would reopen it.

**Healing the party is a placeholder and is named as one.** It is here because
nothing else can heal, not because a defeat should be free. The day an item or a
service exists, this stops being right — and the sentence that will have to be
revisited is this one, not a behaviour nobody wrote down.

The validator refuses a world with no rest point anywhere — one problem, not one
per map — and a map that can reach none through its doors. That second case is
content a defeat cannot recover from, and it is invisible until somebody loses
there.

The metric may still return nothing, for a world built by hand in a test. Null is
a real answer the caller handles; standing back up where you fell beats a crash.

## 10. Testing obligations

- **Slot selection matches the weights.** Over many draws, proportions hold. This
  is the property that a wrong implementation passes every individual test.
- **A level lands inside its slot's range**, both ends inclusive, across the
  degenerate case where `min == max`.
- **The rate check is monotone**: a higher rate never produces fewer encounters.
- **Determinism at a fixed seed** — the same seed gives the same encounter.
- **The four vocabularies stay disjoint**, by extending the existing meta-test.
- **Every authored table loads** into its typed form (spec 09, section 10).
- **Validation rejects a broken map**, proven by fixture maps built to fail: an
  unknown table, a warp to nowhere. A validator with no failing fixture is a
  validator nobody has seen fail.
- **The world's save section round-trips** — part of declaring a section, not an
  extra (spec 13, section 8).

On a **fixture map**, built for the tests and not part of the game, with no
rendering — node logic runs headless, and the suite is already headless:

- **A step into a blocked cell does not move the player, and still turns them.**
  Turning in place is the behaviour most easily lost in a refactor, because a
  blocked step and a step that did nothing look identical from outside.
- **A step off the edge of the map is blocked**, and blocked the same way as a
  wall — not by an error.
- **Stepping onto a warp arrives** at the declared map, cell and facing.
- **A cell inside a zone reports that zone's table**, and a cell outside reports
  none. Zone edges are tested at the boundary cell, which is where an off-by-one
  lives.
- **Encounter checks happen per step and only inside a zone** — the join between
  the native half and the pure one, and the only place a mistake there shows up.
- **The rest-point metric picks what it says it picks**: the nearer of two on one
  map, a map with none reaching one through a door, one door beating two whatever
  the grid distances are, and null when nothing is reachable. A ring of doors
  terminates.
- **Losing teleports and heals**, proven by losing a real battle rather than by
  calling the recovery directly — and losing underground comes up on the map that
  has the camp.

**What no test covers, and this line exists so nobody reads the absence as an
oversight:** whether a map is well laid out, and how movement feels. Those are
design, judged by playing.

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
