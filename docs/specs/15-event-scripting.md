# 15 — Event scripting

**Status:** Draft
**Depends on:** specs 09, 13, 14; decisions 0026, 0036, 0038, 0040

This is what makes a map more than terrain: someone to talk to, a door that stays
locked until it should not, a scene that plays once.

It also inherits a problem the earlier specs created and left here. **Spec 09
forbids conditional logic in content** — "the first `if` in content is the moment
the format became a DSL" — and an event is conditional by nature. A dialogue
branches; a flag opens a door. Section 1 is how that is resolved rather than
weakened.

---

## 1. An event is composed, not written and not parsed

An event is a **subtree of typed nodes** in the map scene. Each node does one
thing; the order and nesting are the event.

Behaviour is GDScript, in the node. Composition is the scene tree. **Nothing is
ever parsed as a language**, so spec 09's rule holds with no exception carved
into it — there is no format to grow conditionals into, because there is no
format.

This also puts events where the world already lives (decision 0038). A map's
people belong to the map, not to a parallel file keyed by map id.

**Rejected: one GDScript class per event.** No format at all and every event
reads as ordinary code. But a hundred people is a hundred near-identical scripts,
and changing how every dialogue closes becomes a hundred edits.

**The cost, named:** a dialogue's diff is a scene diff, and unreadable. This is
the second and last file class where decision 0004's readability criterion is
suspended, for the same reason as the first (decision 0039) — and, as there, what
review would have caught is caught by validation instead (section 7).

## 2. What a step can be

A small set of node types, each doing exactly one thing: say a line, set a flag,
wait, move a character, branch on a flag, run a nested sequence.

The set grows when something needs a step it has not got. **Adding a step writes
GDScript**; it never widens a schema, because there is no schema.

Spec 06 section 8 governs here and is not restated: a step that would need an
`if` among its parameters is a new node type, not a parameter.

## 3. Flags: two kinds, and both are permanent

| Kind | For | Absent means |
|------|-----|--------------|
| Named boolean | "this happened" | false |
| Named integer | "where this quest stands", "how many" | 0 |

**The integer is what stops a quest from being encoded as several booleans.**
Five steps as five booleans permits step 4 true with step 2 false — a state
nothing can describe, nobody will look for, and no event knows how to resume. An
integer moves in one direction and cannot contradict itself.

**A flag id is held in a save.** So the identifier rule of spec 09 section 3
applies unchanged: `snake_case`, stable, and never reused for a different
meaning. Renaming a flag is a migration, not a rename.

**Absent reads as the default**, which is what lets an older save load: a flag a
new version added simply is not there yet. That is spec 13's tolerant read, one
level down.

**A flag this build does not recognise is kept, not dropped** — decision 0036's
argument applied inside a section rather than between sections. A build that has
lost a quest must not silently erase the player's progress through it.

## 4. Events fire at discrete moments only

Three, and nothing else:

- **Interacting** with the cell the player faces
- **Stepping onto** a cell
- **Entering** a map

Nothing polls, and nothing watches a flag waiting for it to become true. Grid
movement gives a moment a beginning and an end (spec 14, section 2), and this is
the second thing that buys — the first was the encounter check.

**What this gives up, plainly:** a door cannot open at the instant the key enters
the bag. It opens the next time the player touches it or re-enters the map. That
is the price of an event never surfacing in the middle of something else, and it
is worth paying: an event that can fire at any moment can fire during another
event.

## 5. An event is atomic

**Its flags land when it finishes.** An event that is interrupted never happened,
and replays from its start.

The alternative — flags landing as they are set — is what the code does naturally
and it is why this has to be written down. It leaves a save holding a quest half
advanced, in a state no event knows how to resume. On mobile the application
*will* be killed mid-cutscene.

Three consequences, all binding:

**An event must be replayable from its start.** A step that cannot simply be
repeated — consuming an item, paying money — has to land in the same commit as
the flags. This is a constraint on how events are written, not only on how they
are run.

**Atomicity covers persistent state, not what is shown.** An NPC walking across
the room mid-event is not rolled back; there is nothing to roll back, because
nothing was saved.

**The player cannot save while an event runs**, the same way they cannot save
mid-battle (spec 13, section 6). The reason is the same one: a save must not hold
a shape that only exists halfway through something.

## 6. Dialogue carries no text

An event holds **line ids**. The text is localisation and lives in L4 — the rule
spec 07 sets for the battle log and spec 09 section 7 sets for content, applied
a third time rather than reopened.

A line of dialogue written into a scene would put presentation text inside world
data, and would make translating the game an edit of every map.

## 7. What is validated

The map validator of spec 14 section 7 gains the event checks, because they are
the same class of error and would otherwise need a second mechanism:

- **a branch reading a flag nothing ever sets** — the door that never opens
- a flag set by nothing and read by nothing — dead, and usually a typo's other half
- a line id with no entry in the localisation table
- an event with no reachable end

The first is the one nothing else catches. A flag name misspelled at one of its
two sites reads perfectly, sets perfectly, and gates something forever. No test
of any single event finds it, because each half is correct on its own.

## 8. Flags reach the save through their own section

The mechanism of spec 13, and the second application of decision 0040's general
rule: **a section belongs to its system**, wherever that system lives. `save/`
holds the mechanism; the world holds its position and whatever owns flags holds
theirs.

That the world's section and this one were written by different systems, at
different times, without either knowing about the other, is the mechanism working
as intended rather than a coincidence.

## 9. Testing obligations

- **Each node type does one thing**, tested alone.
- **An interrupted event leaves no flag set.** The property the whole of
  section 5 exists for.
- **An event replayed from its start reaches the same end state.** Not merely
  that it can be replayed — that replaying it twice is indistinguishable from
  running it once.
- **A branch takes each side** according to the flag, including the absent flag.
- **An absent flag reads as false or zero**, and an unknown one survives a save
  round trip.
- **A flag id round-trips** through the save section (spec 13, section 8).
- **Validation rejects a flag that is read and never set**, proven by fixtures
  built to fail — the same obligation, and the same reason, as spec 14's.
- **Standing still fires nothing.** Section 4's discipline, stated as a test
  because it is the one a polling implementation would quietly break.

## Open points

- **Trainer battles.** An event that starts a battle is the obvious next thing an
  event needs to do, and the handoff is the one the overworld already has: produce
  the participants and stop. What a trainer *is* — a party, a reward, a line on
  defeat — has no spec.
- **NPC movement outside events.** Whether people wander, and what happens when
  one is standing where the player is walking. Section 4 says nothing about it
  because nothing here moves on its own.
- **The localisation format**, and where line ids are declared so that section 7
  can check them. Named as a dependency, not designed here.
- **Shops, money, and an inventory that can be spent from.** Section 5 already
  constrains how they would be written; nothing else about them is settled.
- **Cutscene camera and animation** — L4, specs 16 and 17.
