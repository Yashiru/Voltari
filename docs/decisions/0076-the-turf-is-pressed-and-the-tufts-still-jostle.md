# 0076 — The turf is pressed, and the tufts still jostle

**Status:** Accepted
**Date:** 2026-09-12
**Limits:** decision 0060 — its verdict now covers the tall tufts and not the lawn
**Recorded in:** spec 16, section 12

## Context

The turf did not know a character existed. The tall tufts have reacted since
decision 0060 — a cell rings when it is stepped into — and the lawn underneath
them stood perfectly still while somebody walked across it, which is the one
place the two being different is visible at a glance.

Decision 0060 is emphatic about what a reaction may not be. It rejected the
radial push, the splay along the heading, the wake, the darkening under a foot,
and flattening in as many words: *"flattening is deformation under another name"*.
That verdict was reached on the tall tufts, tuned on a sparse grass tile and
tested on a dense one, and the failure it names is grass that reads as **damage**
rather than as somebody passing through.

The maintainer asked for the opposite here, in as many words: the turf should be
pressed down and stand back up.

## Decision

**The lawn is pressed. A tuft still jostles.** Decision 0060 keeps its whole
verdict over the tufts and stops at the turf.

A press is a place, an age and a width. Blades within the width are turned over
towards the ground, away from the middle of the press, and they come back up over
about a second. Nothing else: no darkening, no bare ring, no wake, and no reading
of anybody's speed or heading.

**Laid over, never shortened.** A blade keeps its length and turns about its
root. Scaling its height would sink it into the ground and leave a bald disc
under anybody standing still — which is precisely the failure 0060 named, arrived
at from the other direction.

**The strongest press wins; presses are not added.** Two footfalls that overlap
cannot press the ground twice, because the blade is already down. This is not a
corner case: a player standing still drops press after press in one spot, and a
sum drives the blade through the floor inside a second.

**Where somebody stands arrives as a list, not as a field.** A fixed array of
world positions with an age each, handed to the scatter shader every frame. The
shader keeps no state, exactly as `GrassField` keeps none for the tufts.

**A press is spaced against the presser's own radius**, not against a clock, so a
walk and a run leave the same footprints instead of a sprint leaving a dotted
line. The width arrives per contact from `VltFreeWalker.RADIUS`, which is already
bounded under half a cell — a number in the shader would be a second opinion about
the same thing.

## Why the two herbs are not one mechanism

They were offered as one and the maintainer chose to keep them apart. The reason
holds up, and it is the reason 0060 exists:

**A tuft is a model and the lawn is a scatter.** A tuft is one mesh an artist
made, and 0060's whole finding is that *changing its shape is what read as
damage* — so the only thing left to vary is which way it leans. A blade of turf
is five triangles placed from an index, with no silhouette anybody authored and
nothing to preserve. Laying one over is not deformation of an artist's work; it
is where the blade is put.

**You walk through tufts and on top of turf.** A tuft is knee-high and you part
it or you do not; nine centimetres of lawn is under your foot. A single mechanism
would have to mean both, and the amount that reads on one is the amount that
ruins the other — which is the exact shape of the mistake 0060 was written about.

**They already move differently and always have.** A tuft leans as one piece
because a clump does; a blade of turf is asked for the wind at its own feet so a
gust crosses the lawn continuously. The wind is shared (`wind.gdshaderinc`) and is
*asked different questions* by the two. The press is the same: one shared idea,
two readings.

What this costs is stated rather than hidden: **there are now two objects that
tell grass about a walker**, `GrassField` and `TurfTreading`. They are not two
ways to do one thing — one rings a cell and one presses a point — but they are
adjacent enough that a third would be a smell.

## Options rejected

**A trample field on the grid the patch already has.** The obvious answer, and it
nearly won: the room field is already there at eight texels a metre, already
carries distances in metres, and a press is one more channel. It gives trails and
any number of actors for one cost. Rejected on price — a sixty-four metre patch
is a 512-square field, and decaying it is a quarter of a million texels rewritten
every frame for a quantity that is never more than a few dozen numbers. Doing that
decay on the GPU means a viewport pass and an extent policy, which is real
machinery for a feature that has an exact cheaper answer. **If long-lived trails
are ever wanted, this is the option to come back to**: the list cannot express a
path somebody took ten seconds ago and is not meant to.

**A global shader uniform.** One walker handed to every shader that bends, with no
per-material push, which is what this project's instincts point at. Rejected on a
fact: a Godot global shader parameter cannot be an array, so it cannot carry more
than one actor without one named uniform per actor. Creatures and NPCs are in
scope for this.

**Extending the tufts' jostle to the turf.** The least new code. Rejected because
its trigger is a cell being entered and movement stopped being discrete at
decision 0058 — a lawn that goes down once per cell crossed, in a disc of 0.62
metres, is not a footstep. It would also have made 0060's verdict cover the lawn
by accident rather than by decision.

**Tuning the press down until it stopped looking like damage.** Named here only
because 0060 rejected the same move and the reasoning is worth not relearning:
the problem would be the shape of the effect, not its size.

## Consequences

**The tufts' cell-entry trigger rests on a superseded sentence.** Decision 0060
justifies it with *"Movement is grid-locked (spec 14, section 2) and this now is
too"*, and decision 0058 made position continuous. It still fires and it still
looks right, because a cell is crossed in about half a second and that is the
rhythm footfalls have. **It is not touched here** and it is written down so that
whoever does touch it knows the justification is older than the movement.

**A ceiling of thirty-two live presses**, which at one press every fifteen
centimetres is about two seconds of one person walking. Past it the oldest is
forgotten first — the one that has recovered furthest, and so the least visible
thing to lose. It is a limit on presses still recovering, not on actors.

**Nothing is stored.** A press that has recovered is gone, so what is held is
never a record of where anybody has walked. That is the same promise
`turf_patch.gd` makes about geometry.

**The lawn nobody is standing on is arithmetically unchanged.** The press
interpolates from the wind's own lean, so at no press the blade's axis is the
expression it was before this existed. A feature that moved the wind by a percent
everywhere would be a regression bought with a feature, and an invisible one.

**Not measured: what the loop costs on a phone.** It is up to thirty-two distance
tests per blade in a process stage that already does two texture reads and four
hashes, bounded by the live count so a still player costs one. Spec 16 already
records that nothing about these shaders has been measured on the Mobile renderer,
and this does not change that.

**Not settled by a render.** Decision 0060's closing rule is that one asset is not
evidence and a claim about how grass looks means having rendered it. The turf has
no preview harness — `tools/grass/` drives the tufts — so this went in on the
mechanism being right, and **how it reads is still to be judged by looking.**
