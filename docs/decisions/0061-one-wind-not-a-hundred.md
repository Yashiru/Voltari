# 0061 — One wind, not a hundred

**Status:** Accepted
**Date:** 2026-09-10
**Supersedes in part:** decision 0059 — its harness and its method stand, its
per-cell variation does not
**Recorded in:** spec 16, section 12

## Context

Decision 0059 gave every tuft its own phase, its own stiffness, its own shade and
its own rotation and size, on the reasoning that a `GridMap` draws the same mesh
at every cell and the repetition is the tell of instanced grass.

That reasoning was about a **still** field. Set moving, it produces the opposite
of wind: a hundred tufts each twitching to its own clock, at its own rate, by its
own amount. The maintainer's words for it were *aléatoire* and *élastique*, and
both are exactly right — it was noise with a spatial extent, not air.

Nobody asked for the rotation and the size variation either. They were added on
the same reasoning and they change a map that is already painted.

## Decision

**One wind for the whole world, and no per-cell anything.**

The lean at a point is two travelling waves summed — a long one, thirteen metres
and slow, which is the gust crossing the field; and a shorter one at a different
speed, which exists only so the sum is not a sine. Both are functions of world
position and time alone.

That is what makes a gust **travel**: a blade's phase comes from where it stands,
so neighbours are in step and distant grass is not. Per-tuft phase destroys
exactly this — if every blade has its own offset there is no wave to see.

Under both, one slow breath over about eleven seconds, global, so the whole field
lulls together. A lull that happened per tuft would not be a lull.

**Dropped entirely:** per-tuft phase, per-tuft stiffness, per-tuft shade,
per-cell rotation, per-cell size.

**Kept:** the shading that follows the blade rather than a random number — darker
in the thatch, warmer at the tip. It varies along a blade, not between blades, so
two tufts side by side are the same colour.

## The defect this uncovered

The maintainer reported a wind that was strong, fast and random after it had been
tuned to a fifth of its strength and made coherent. Both were true at once:
**a `ShaderMaterial` remembers what it was given, and a stored value outlives the
shader that set it.** The library on disk still carried `gust_strength = 0.34`
and `stiffness_spread = 0.45` from an earlier build, and those won over the new
defaults.

So the tile library builder now **disowns** every parameter it does not own,
setting it back to the shader's default. It owns four — the albedo, its texture,
and the hinge and height it measures. Art direction belongs to the shader file,
and the runtime sets the rest every frame.

Without that, tuning a number in a shader changes nothing on any library saved
before the change, and the shader on disk looks guilty.

## Options rejected

**Keeping the variation and slowing it down.** The first instinct, and it does not
converge: the problem is not the rate, it is that a hundred independent clocks
cannot add up to one air mass however slowly each of them ticks.

**Variation in amplitude only, with a shared phase.** Tempting — tufts would move
together but not identically. Rejected because stiffness that varies per cell is
still a hundred numbers where the world has one, and because the thing it buys
back is repetition-breaking on a *still* field, which is a placement problem and
belongs to whoever paints the map.

**Telling the maintainer to rebuild the library.** It would have fixed the symptom
in one click and left the trap armed for the next shader change.

## Consequences

**A field of identical tiles looks identical when still.** That is now accepted
rather than hidden: it is a property of painting one tile everywhere, and the
answer is a palette with more than one grass in it, not a shader pretending.

**A shader change now takes effect on the next library build**, and a build clears
whatever the last one left behind. Nothing on a grass material survives that the
builder did not put there deliberately.
