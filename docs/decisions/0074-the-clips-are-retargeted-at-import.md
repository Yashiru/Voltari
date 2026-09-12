# 0074 — The clips are retargeted at import, and a character model is a rig

**Status:** Accepted
**Date:** 2026-09-12
**Recorded in:** spec 16, section 11

## Context

Eleven animations arrived as separate FBX files, and the direction changed with
them: **a character `.glb` is from now on a rigged model with no animations in
it**, and every clip lives in `game/assets/characters/humanoid_animations/`.

They do not fit the character. Measured rather than assumed:

| | the clips | `main-char.glb` |
|---|---|---|
| bones | 65, with fingers | 27, without |
| rest pose | T-pose | A-pose |
| hips | 1.043 m | 0.841 m |
| thigh + shin | 0.889 m | 0.635 m |

The names match — both are `mixamorig` rigs — and that is the trap. The clips
load, the tracks resolve, and the result is wrong in two ways at once: the arms
fold into the chest, because the bone axes differ by a roll of about 180° on
every shoulder, arm and leg; and the whole body floats **19 to 26 cm** above the
ground, because the hips' position track is in the source rig's scale.

Every file also carries one take called `mixamo.com`, so all eleven import as an
animation named `mixamo_com`.

## Decision

**Both the model and the clips are imported through one committed `BoneMap` onto
`SkeletonProfileHumanoid`, with the rest fixer's `overwrite_axis` and
`normalize_position_tracks` on.** The map is
`game/assets/characters/mixamo_humanoid.tres`, twenty-two bones of a Mixamo rig
against the profile's names.

The importer then rewrites both skeletons onto the profile's reference axes,
renames their bones, and calls the skeleton node `GeneralSkeleton` with a unique
name. A clip's tracks address `%GeneralSkeleton:Hips`, and that resolves against
**any** character imported the same way. There is no glue at runtime: the library
is added to an `AnimationPlayer` and played.

Measured after the change, across all eleven clips: the lowest a toe reaches is
between 1.5 cm below and 2.1 cm above where the toe rests. The character stands
on the floor.

**Each clip imports as an `AnimationLibrary`, not as a scene**
(`importer="animation_library"`). There is no mesh in any of them, and importing
eleven scenes would instance eleven skeletons to throw away.

**The slot name is the file name.** Every take is called `mixamo_com`, so the
name that means anything is the one on disk. `HumanoidClips` is where that is
turned from a coincidence into a rule, and the tests hold the folder and the
vocabulary to each other in both directions.

**`main-char.glb` is imported with `animation/import=false`.** It still carries
the three clips it arrived with; turning them off is what makes the library the
only source rather than the first of two.

## Options rejected

**A pipeline outside the repository**, baking the clips onto the character's
armature in Blender and committing one animation-only `.glb`. This is what the
creature models already do (spec 16), and it would allow an artist to fix a
contact by hand.

Rejected because it puts a manual step between an asset and the game that CI
cannot check, for a problem the engine solves exactly. It stays the right answer
the day a clip needs *authoring* rather than converting — and that is a different
day.

**Correcting it at runtime**, scaling the hips track by the ratio of hip heights
when the library is built. Tried, and it works for the height: 0.8067 puts the
feet within two centimetres. It does nothing at all for the bone axes, which is
the half of the problem that makes the character look broken rather than tall.

**Re-exporting the clips bound to this character.** The cleanest input, and not
available: the rig the animations came on is not the rig the model was built on,
and nothing in the repository can re-run that export.

**Leaving the bones named `mixamorig_…`** by turning the renamer off. The map
alone is enough to fix the axes. Rejected because the profile names are what make
a *second* character interchangeable with the first, which is the whole point of
moving the clips out of the model.

## Consequences

**The bone names changed**, so anything that looked up `mixamorig_Hips` now looks
up `Hips`. Twenty-two of the twenty-seven are renamed; the five the profile has no
name for — the head top, the two fingertips, the two toe ends — keep theirs, and
the tools that measure ground clearance still ask for `mixamorig_LeftToe_End`.

**`tools/characters/measure_gaits.gd` is gone**, replaced by
`measure_clips.gd`. The old one could not measure what matters here, and keeping
both would have been two ways to ask one question.

**The gait speeds changed, and the method behind them changed more.** They used to
come from a cadence times a step length taken as a fraction of the character's
height. The cadence was honest; the fraction was anthropometry, and this character
is 1.70 m tall with 0.64 m legs and a head a third of its height. An in-place clip
has the planted foot sliding backwards at exactly the ground speed, so the speed
is now read off the foot, on this rig, after the retarget — 1.33 m/s walking and
3.33 m/s running, both feet agreeing to within 2%. The world moved from 3.6 to
3.33 m/s as a result.

**Eight of the eleven clips have nowhere to go yet.** The four turns need a system
(decision 0075 does not cover them), the throw needs the player drawn in battle,
the two stair loops need an overworld with more than one storey, and the fishing
idle is a stance around a rod that does not exist. They are named, imported and
tested; nothing plays them. That is deliberate and it is written down rather than
left to be rediscovered.

**The fingers are dropped, and two fingertips are not.** The clips animate 65
bones and the model has 27, so 38 tracks resolve to nothing — which is what should
happen. `LeftHandMiddle4` and `RightHandMiddle4` exist in both and hang off
different parents, so their tracks land on a bone that means something else. They
carry 254 and 491 vertices between them, at the very ends of the fingers. Named
here because it is the one thing the retarget does not fix, and nobody should have
to find it twice.
