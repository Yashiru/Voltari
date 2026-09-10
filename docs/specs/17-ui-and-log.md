# 17 — UI and battle log consumption

**Status:** Draft
**Depends on:** specs 03, 07, 12, 16; decisions 0016, 0017

The log already exists: ordered, per-side filtered, and carrying no text at all.
This is what turns it into something a player watches.

**Scope: battle only.** The reader, the battle HUD, the command menu. Screens for
party, bag, boxes and shops wait for the systems they display to have a
specification — this half is the hard one, and the only one with an event stream
to honour.

---

## 1. Everything the player sees of a battle comes from the log

Never from the state.

Spec 07 gives each side its own filtered view: an opponent sees a health
*proportion*, not exact HP, because `transformed` events carry a declared
reduction. **A HUD that read the state would walk straight around that filter**,
and the day PvP arrives the display would already be showing a side what it is
not entitled to know. That is not a bug you find; it is a rewrite you postpone.

The cost is real and small: the reader rebuilds what it displays — health,
status, who is out — by replaying events. Spec 07 made that a read rather than
arithmetic, because **events carry resulting values, not deltas**. Replay assigns.

### It starts from a view, it does not conjure one

Invariant 8 says replaying a log **onto the initial state** reproduces the final
state. This is the same sentence about a view: the reader is handed the opening
position and advances it.

A view built from a log alone could not exist, because a log never announces what
was already on the field when it started. The differential that proves this
works — a view read from the state against a view advanced by the filtered log —
is the test that makes decision 0049 cost nothing in fidelity.

### Two things the log does not say, and one it should not

Writing that differential found both.

**A switch announced no health**, so a HUD would have drawn a full bar and then
seen it jump. The event now carries it, transformed: exact for its owner,
hundredths for everyone else. **A switch announced no level** either, and a
player decides on that number.

**Your own creature's moves are not in the log, and must not be.** They were
never a battle event; your party is simply yours. The reader is handed it.

That last one is why the mechanical form of this rule names the *state* and not
the creatures in it: a state is reach — from one you can read the opponent —
while a creature handed in bypasses no filter. Nothing under the reader may
reference `VltBattleState`, and a lint holds it.

## 2. The reader is a queue drained with `await`

Take an event, play what it looks like, wait for that to finish, take the next.

**`await` is banned in the core and correct here**, and the difference is not
taste. The turn engine and the event run suspend (decisions 0012 and 0044)
because they must hold nothing across a save and must be testable without a
frame. A log reader persists nothing, is never saved, and exists precisely
*because* time passes. Suspending it by hand would buy nothing and cost a driver
loop.

This is stated so that a reader who has met the other two machines does not read
this as an oversight.

**The reader is where the game's pace lives.** No other layer has an opinion
about how long anything takes, which is what lets pacing be tuned without
touching a rule.

## 3. An unknown event must not stop a battle

The log is complete by obligation (spec 07, section 1) and will grow. A reader
that failed on an event kind it did not recognise would make **adding a mechanic
a UI change**, every time.

So: an unrecognised event is skipped for display, its state effect still applied,
and reported loudly in development and silently in a release. The battle
continues.

## 4. Skipping plays faster, it does not play less

A player will hold a button. Skipping runs the remaining events immediately; it
never drops one.

**The end state must be identical whether a battle was watched or skipped.** That
is a test, not an intention — and it is the property that stops "skip" from
quietly becoming a second, shorter code path.

## 5. Text is Godot's own translation

Keys and `tr()`, not a format of our own. Plurals, per-language loading and
fallbacks are solved by the engine, and rebuilding them in YAML would cost a
great deal to arrive back where we started.

The core emits identifiers and nothing else (spec 07, section 6). **The reader is
the single place an identifier becomes a sentence**: it turns an event into a key
plus arguments.

**Every key the reader can ask for is checked to exist**, in both directions: a
key nothing translates would print as its own name, and a key nothing asks for
reads as a translated game long after its event was renamed.

That check is engine-side rather than in the content build, for the reason the
map validation is (spec 14, section 7): **the keys live in GDScript**, and only
GDScript knows which ones something can produce. The build reasons about YAML.
Spec 15's dialogue lines need the same check and will get it the same way.

## 6. Asking a creature to move

Spec 16 gives every creature the same clip vocabulary; this is what asks for it.

A damaging move plays `attack_physical` or `attack_special` on the actor and
`hurt` on the target; a faint plays `faint`. **The mapping is from event kind to
slot, in one place**, so a creature that has an unusual clip does not need the
reader to know about it.

Where a slot has several takes, the reader picks among them — which is the only
reason a slot is a list at all.

## 7. The command menu is a decider

The player's menu produces commands, which is exactly what the AI does
(`docs/architecture/layers.md`, L0bis). It implements the same role against the
same vocabulary.

That is not an analogy. It means a battle does not know whether it is being
played by a person, and it is why spec 12's AI could be written before any UI
existed.

## 8. What the HUD shows

Health, status, which creatures remain, and whose input is wanted. All of it
derived from section 1's replay, all of it therefore already filtered.

**Nothing on screen may be something the log did not say.** A HUD element with no
event behind it is a HUD element that will be wrong the first time a mechanic
changes.

## 9. Testing obligations

- **The reader handles every event kind the core can emit.** A meta-test, because
  spec 07 makes completeness an obligation and this is the other end of it.
- **Skipping and watching end in the same state.** Section 4's property.
- **An unknown event is skipped, not fatal**, proven with an event kind invented
  by the test.
- **The reader never touches battle state** — a lint over its directory, in the
  spirit of the purity lint, because this is a rule about what may be referenced
  rather than about behaviour. It names `VltBattleState` and not the creatures
  in it; section 1 says why.
- **Every text key the reader can produce exists** in the translation table, and
  the table declares nothing nobody asks for.
- **The view advanced by the filtered log agrees with the view read from the
  state**, from either seat. Replaying the *unfiltered* log would hand a side
  figures it has no right to and the test would pass by cheating.
- **Every event-to-clip mapping names a slot in the vocabulary** (spec 16,
  section 4), checked rather than trusted.
- **A filtered log drives a complete HUD.** Given only what one side may see, the
  display must have every value it shows — the test that would catch a HUD
  quietly needing something private.

## Open points

- **Out-of-battle screens.** Party, bag, boxes, shops. Each waits for the system
  it displays.
- **Audio.** Named in L4 and untouched here; it hangs off the same event stream
  and should probably be a second reader rather than a branch in this one.
- **Camera and framing.** Decision 0020 freed the camera and nothing has decided
  what it does with that freedom.
- **Accessibility** — text size, colour-blind-safe type colours, reduced motion.
  The last one interacts directly with section 4 and is not free.
- **How long anything takes.** Section 2 puts pacing in one place; it does not
  say what the numbers are, and they are a design question rather than a
  structural one.
