# 0076 — A turn on the spot is a clip, warped onto the angle

**Status:** Accepted
**Date:** 2026-09-12
**Recorded in:** spec 16, section 11

## Context

Facing was a rate. `WalkerGait.turned` moved the body towards its heading at
14 rad/s whatever it was doing, and a character standing still who was asked to
face behind them swivelled — feet planted, body rotating, a turret.

Four turn clips arrived with the rest (decision 0074) and none of them turns by
what its name says. Measured off the clips themselves:

| clip | delivers |
|---|---|
| `turn_left_90` | +90.0° |
| `turn_right_90` | **-102.6°** |
| `turn_left_180` | +176.1° |
| `turn_right_180` | -175.1° |

## Decision

**Standing still, past sixty degrees, the turn is a clip — and the body's yaw is
driven by that clip's own rotation.** Not by a rate underneath it: a turn clip
does not rotate at a constant rate, and a body that did would have the feet
planted in one place while the hips passed through another. The clip says *how*
the turn is spread along its length; the code says only how far it goes.

**Warped onto the exact angle.** The clip's rotation is scaled by
`wanted / delivered`, so a request for 140° is served by the half turn played
short. Outside a band of 0.65 to 1.45 the stretch starts to show, so there the
clip delivers what it can and the ordinary rate closes the few degrees left —
underneath a turn already happening, where nobody looks.

**What each clip delivers, and how, is read off the clip when the graph is
built.** The hips are the root bone, so their rotation track *is* the body's
rotation: sampling it gives both the total and the curve, and there is no table
for anybody to keep in step with the assets. `WalkerGait.pivot_by` takes that
table as an argument rather than holding one.

**Moving, nothing changes.** Walking already turns the body and the legs are
already carrying it. A step also gives up on a turn in progress, for the same
reason: a body finishing a swivel it no longer needs is the one thing here that
reads as the character ignoring the player.

## Options rejected

**Root motion.** `AnimationTree.root_motion_track` on the hips gives the frame's
rotation delta directly, which is exactly the number wanted, and is what root
motion is for. Rejected because the track it consumes is the same one that
carries the walk's vertical bob and the throw's crouch: taking it for the turn
takes it from everything. Re-applying the part that was wanted would be two
mechanisms for one track.

**A constant rate under the clip**, timed so the two finish together. Cheaper,
and wrong in the only way that matters: the feet skate, which is the artefact the
clip was brought in to remove.

**Playing the clips at face value** and accepting where they land. Twelve degrees
out on one of the four, every time, with nothing in the code to explain it.

**A turn clip while walking**, blended into the gait. That is a lean, not a
pivot, and it is a different clip nobody has.

## Consequences

**Sixty degrees is a number, and it is the only one here that is not measured.**
Under it a turn is not worth a clip — a character who plays a one-second half
turn because the stick moved is a character who never goes where they were
pointed. Over it the clip is always the nearest on the same side: a turn one way
is never served by one that goes the other, however close the magnitudes are,
because the feet cross the other way and everybody can see it.

**A turn is carried on the frame it starts.** It would otherwise spend its first
frame standing still, which answers the player one frame late every time for no
reason visible in the clip.

**`playing()` still reports the legs.** A turn is laid over them rather than
instead of them, so what the character is doing underneath is unchanged — and a
test that asks what it is playing gets the same answer during a turn as before
one.
