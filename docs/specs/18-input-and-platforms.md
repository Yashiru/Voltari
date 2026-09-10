# 18 — Input and platforms

**Status:** Draft
**Depends on:** specs 13, 14, 15, 17; decisions 0038, 0044

The last document in the plan before the deferred one. It is short, because most
of what a player does has already been decided elsewhere: a battle command is a
decider (spec 17, section 7), a step is a step (spec 14, section 2), and an event
fires at three named moments (decision 0043).

What is left is how a finger, a key and a stick all become the same thing.

---

## 1. One intent, several sources

**Nothing downstream knows what the player touched.** The world receives a
direction and a request to interact; a battle receives a command. Both already
exist and neither gains a variant for touch.

| Source | Gives |
|--------|-------|
| Keyboard | a cardinal direction, pressed or not |
| Gamepad stick | a vector |
| Floating touch stick | a vector |

Two of the three are analog, so the layer that turns a vector into a direction
serves the gamepad and the finger alike. A keyboard is that same layer handed a
vector already pinned to an axis.

## 2. The stick is quantised, and the grid never hears about it

A floating stick: touch anywhere in the walking area, the stick appears under the
finger, dragging gives a direction. It is the control players expect on a phone,
and the reason it needs a specification is that **a stick is continuous and the
world is not** (decision 0038).

Four rules turn one into the other:

**A dead zone.** Below it, no direction at all. Without one, a resting thumb
walks.

**The dominant axis wins.** The larger component decides; the other is discarded.
There are no diagonals, because there are no diagonal steps.

**A bias toward the direction already held.** Near 45° the dominant axis flips on
a tremor, and without this a player walking north-east zigzags one cell at a
time. The new axis must beat the current one by a margin before it takes over.

**Both axes pushed hard is a staircase** (decision 0056). Above a floor on each
axis separately — cleared by two keys held, and never by a tremor — the step
alternates: east, north, east, north, one cell at a time and with no pause
between them. Every one is an ordinary step, so there are still no diagonal
steps and nothing below this reads it as one. The eye supplies the diagonal.

The bias governs the band *below* that floor, which is where its stated reason
lives: a tremor is a small second axis. Above it, both axes are deliberate and
there is nothing to protect the player from.

**A flick turns, a hold walks.** Pushing a **new** direction for less than a step
turns the character without moving them — the thing grid games do that players
never notice until it is missing, because it is how you talk to somebody standing
beside you.

A push in the direction already faced is not a new direction, and walks at once.
Applying the flick there makes every tap a turn to where the character already
looked, which is a tap that does nothing at all however many times it is
repeated. The rule is about turning to face something beside you; it has nothing
to say about a direction you are already facing.

The margin, the floor, the dead zone and the flick's duration are numbers, not
structure. They are named in one place and tuned by feel; none of them is a rule.

**What this buys is that section 1 stays true.** The world's `step(direction)`
is unchanged, the overworld tests keep running on fixture maps with no input at
all, and a phone and a keyboard cannot drift apart because they meet before the
world does.

## 3. Backgrounding saves when it safely can

On a phone the application will be killed. Two existing rules say when a save
must not happen: not mid-battle (spec 13, section 6) and not mid-event
(decision 0044).

So: **on being backgrounded, save if neither holds, and otherwise do nothing.**

That recovers almost all of a session, because almost all of a session is spent
walking. The two exceptions already state what they cost — a battle lost, a
cutscene replayed — and neither is reopened here.

An automatic save writes the same way any other does: to a temporary file, then
over the real one (spec 13, section 7). Being interrupted *by the thing that
prompted the save* is exactly the case that mechanism exists for.

## 4. Settings are not save data

Key bindings, volume, language and text speed live in **their own file**, beside
the saves and not inside one.

They are not the player's progress. They survive deleting a save, they are shared
by every save, and losing a playthrough must not silently reconfigure somebody's
controls.

They are written the same way, for the same reason: a settings file half-written
by a crash is a game that will not start.

## 5. Platforms

**Desktop, Android and iOS.** All three are the intent, and they are not equally
knowable from here.

| | Can be built | Can be tested here |
|---|---|---|
| Desktop | yes | yes |
| Android | yes | yes |
| iOS | needs Apple hardware and an account | **no** |

iOS being in scope is a statement about the design, not about the evidence.
Anything specific to it is written from documentation rather than measurement,
and this table exists so that nobody later mistakes one for the other.

Three consequences hold whatever the platform:

**The renderer is the mobile one**, already set. Spec 16's asset budget is
addressed to it.

**The save location is the platform's, and nothing else knows.** Spec 13 put file
handling in one class precisely so that this is one line rather than a rule.

**Every export preset excludes the placeholder directory.** The guard of decision
0027 checks each of them, so adding a platform means adding a preset the guard
will immediately have an opinion about.

## 6. Testing obligations

- **The quantiser is a pure function and is tested as one.** A vector in, a
  direction out — the dead zone, the dominant axis, the bias near 45°, and the
  flick that turns without moving.
- **A tremor at 45° does not zigzag**: a sequence of vectors wobbling across the
  diagonal yields one direction, not an alternation. This is the property the
  bias exists for and the one that cannot be seen by trying it once.
- **A keyboard and a stick produce the same steps** for the same intent, which is
  section 1 stated as a test rather than a hope.
- **Backgrounding mid-battle writes nothing**, and backgrounding in the world
  writes a save. Both proven, because the interesting one is the refusal.
- **Settings round-trip**, and a malformed settings file starts the game with
  defaults rather than not at all.
- **Every export preset excludes the placeholders** — already the guard's, and
  named here because adding a platform is when it matters.

## Open points

- **Rebinding**, and whether a touch layout can be moved or resized. The file
  exists to hold the answer; nothing decides what is rebindable.
- **Gamepad on mobile**, which is real and which nothing here covers.
- **What the touch layout looks like** in battle, where the menu is buttons and
  there is no stick. Spec 17 built buttons and said nothing about their size.
- **Haptics**, and whether anything vibrates.
- **Accessibility of the stick** — one-handed play, left-handed layout, and a
  hold-to-walk that some players cannot sustain.
