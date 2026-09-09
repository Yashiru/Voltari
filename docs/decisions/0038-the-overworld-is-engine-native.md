# 0038 — The overworld is engine-native; its rules are not

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 14, sections 1 and 2

## Context

Every layer written so far is pure computation: language only, never the engine,
enforced by a lint. The overworld is the first thing that cannot follow that rule
in full — a map is drawn, walked and collided with.

The question was how much of it to keep pure anyway. A tile grid is a
two-dimensional lookup and a warp is a table; both could have lived in a pure
`world/` module with Godot reduced to drawing, which would have made position and
flags a save section for free and made "does this warp arrive where it should" a
test with no scene tree.

## Decision

**The map is ordinary Godot** — tiles, a character body, area triggers. The world
state lives in the scene tree. The maintainer chose this.

**The world is still tested, on fixture maps**, for everything a test can reach:
a blocked step, a warp arrival, a zone boundary. What the scene tree costs is not
coverage but the *kind* of coverage — see the consequences.

**The rules that carry numbers stay pure**: whether an encounter happens, which
slot is drawn, at what level. They sit in L1 with the other out-of-battle rules,
under the purity lint, and are tested normally.

**Movement is locked to the grid**, with rendering interpolating between cells.

## Why the split falls there

The purity discipline is not a general good; it buys a specific thing, which is
the ability to detect code that is **wrong quietly**. A damage formula off by one
plays for months unnoticed. A warp that arrives in the wrong place is visible the
first time it is walked, and no test suite finds it sooner than the first
playthrough does.

So the line falls between code that can be subtly wrong and code that can only be
obviously wrong. An encounter distribution is the first kind — a slot drawn 1.4
times too often is indistinguishable from luck in any single draw. Tile collision
is the second.

Grid movement is what makes the pure half well-defined: it gives **a step** a
beginning and an end, so the encounter check has something to happen per. Free
movement would replace it with a distance threshold — a constant with no
defensible value.

## Options rejected

**A pure world simulation**, with Godot only drawing and feeding input.
Genuinely attractive: one discipline across the whole engine, position and flags
savable with no bridge, and warps testable.

Rejected by the maintainer. It also asks the project to reimplement collision,
movement and zone detection — the parts Godot exists for — to gain coverage over
code whose failures are already loud.

**Keeping the world native but drawing its randomness in the scene.** Fewer
pieces: a node calls the engine's RNG when the player steps. Rejected because it
puts a distribution somewhere nothing can test and nothing can replay, which is
the exact failure the purity rule was written to prevent, relocated rather than
avoided.

## Consequences

**The world gets the weakest of the project's three test pillars.** Spec 05 rests
on a differential against the oracle, invariants under fuzzing, and mutation
testing. None of the three reaches a scene tree: fuzzing a world means driving a
node graph, and mutating it means rebuilding that graph per mutant, which is
exactly what makes the core's mutation pass affordable and the world's not.

So the world is covered by **example-based tests on fixture maps** — real tests,
naming real behaviours, at a lower standard of evidence than anything below L1.
That difference is a property of where the code lives, not an effort skipped, and
spec 14 section 9 lists both what is covered and what is not.

Two things sit alongside them: the build validates every cross-reference a scene
cannot guarantee (decision 0039), and the numeric half is tested like the rest of
the engine.

What no test reaches at all is whether a map is well laid out and how movement
feels. Those are design, judged by playing, and no amount of coverage would have
answered them.

**The engine gains a Godot-dependent directory**, `addons/voltari/world/`, which
the purity lint does not cover. `platform/` was already such a place; this is the
second, and both are named in the layout rather than discovered.

**Saving needs a bridge**, since the world's state is held by the engine and the
save deals in dictionaries. Decision 0040.
