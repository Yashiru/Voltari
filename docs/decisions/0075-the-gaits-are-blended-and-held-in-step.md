# 0075 — The gaits are blended, and held in step

**Status:** Accepted
**Date:** 2026-09-12
**Recorded in:** spec 16, section 11

## Context

The character used to pick a clip. `WalkerGait.moving_at` chose the nearest
authored speed, `AnimationPlayer.play` cross-faded to it over 0.18 s, and the
playback rate was stretched to cover the gap. That is a switch with a fade on it:
at one speed the legs are walking, a hundredth of a metre per second later they
are running, and the two are different postures.

## Decision

**Standing, walking and running are one continuous thing, and they are played as
one.** An `AnimationTree` holds a small blend graph: the two gaits mixed against
each other, and the result mixed against the idle. Both mixes are a function of
the ground speed and of nothing else.

- idle → walk is `speed / 1.33`, clamped
- walk → run is `(speed - 1.33) / (3.33 - 1.33)`, clamped

Both numbers are the speeds the clips were authored for (decision 0074), so
neither mix is a threshold anybody picked.

**The two gaits are held in step, and that is the part that makes it work rather
than merely compile.** A walk cycle is 1.033 s and a run cycle is 0.700 s. Blended
at their own rates they drift apart within a second: the mixture puts one foot
down while the other clip is lifting it, and the character reads as limping. Each
gait sits behind an `AnimationNodeTimeScale` driven so that **both turn one cycle
in the same time**, and that time comes from the speed — the cadence is
interpolated between the two the clips were made at. A gait at the speed it was
authored for has a rate of exactly one.

Measured: the lowest a toe reaches, held at each speed for two and a half
seconds, stays between 4 cm below and 2.4 cm above where the toe rests, at every
speed from standing to running. Before the gaits were held in step the same
measurement had the left foot hovering **9.5 cm** off the ground at 2.3 m/s and
15 cm at a full run.

**Both mixes are synchronised.** The clip being faded out keeps turning rather
than freezing where it was and jumping when it comes back.

**The tree is advanced by hand**, from the same `delta` that moves the walker,
and built in code rather than authored as a `.tres`. Every number in it is
measured and lives in `WalkerGait`; a resource holding them again would be a
second place for them to be wrong.

**The blend chases the speed rather than being it.** A stick released goes from
full to nothing in one frame, and legs that answered that exactly would change
gait inside 16 ms — a cut wearing a blend's clothes. The blend follows at
12 m/s², which is under a fifth of a second across the whole range.

## Options rejected

**Keeping the cross-fade.** One clip at a time, `play(name, 0.18)`. It is what was
there, it is four lines, and every test of it passed. Rejected on what it looks
like: the gap between 1.33 and 3.33 m/s is most of the speeds the player actually
travels at, and in all of it the legs are doing one of two things rather than the
thing in between.

**`AnimationNodeBlendSpace1D`** — one axis in metres a second with a clip at each
authored speed, which is the obvious shape and reads better than four nodes. It
was written and then withdrawn: holding the gaits in step needs a rate per clip,
a blend space has no room for one, and the alternative its nodes offer —
`use_custom_timeline` with `stretch_time_scale` — **stops advancing** once the
speed settles. Measured as a pose frozen for as long as the speed is held. Two
plain `TimeScale` nodes do the same job with nothing surprising in them.

**Scaling the whole tree instead of each gait.** One rate, applied above the
mixes. It would drag the idle with it, and an idle played at 1.4 is a character
breathing like it has been running — which it has not, because it is standing
still.

**Extrapolating the cadence below a walk.** Somebody edging forward should take
slower steps, so the line is followed downwards rather than clamped at the walk's
own cadence. What keeps that honest is the existing rate band: outside 0.80 to
1.25 a cadence stops reading as a gait, so under a walk the error is allowed to be
a sliding foot rather than an impossible one.

## Consequences

**`playing()` answers a different question.** A blend has no single clip, so it
reports the gait nearest the speed being shown — the one a viewer would name. The
number behind it is `shown_speed()`, and that is what a test should assert when it
means the blend rather than the label.

**A test that asserted "running" at a seam now asserts "not standing still".**
Nine frames into a step the legs are genuinely part way between the two gaits, and
which one they are nearest to on the way up is not a fact worth pinning.

**The turns are not in the graph.** Turning is still the continuous yaw at
14 rad/s that it always was; the four turn-in-place clips are imported and
unplayed. They need the body's rotation driven by the clip and warped onto the
exact angle asked for — the clips deliver 89°, 102°, 176° and 175° rather than the
90 and 180 they were ordered as — and that is a system of its own, not a fifth
node in this one.
