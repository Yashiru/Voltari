# 0065 — Roughcast is stippled, and fades out

**Status:** Accepted
**Date:** 2026-09-11
**Builds on:** decisions 0062 and 0063 — the shared look, and the two layers
already fighting flatness
**Recorded in:** spec 16, section 9

## Context

The two layers of decision 0063 work on everything and are deliberately quiet.
The maintainer asked for something else: a **rendered, roughcast surface** — the
granular skin of a plastered wall — to be put on **chosen models by hand**, not on
the whole palette.

Two things had to be true at once. It had to belong to the printed look rather
than sit on top of it, and it had to survive a camera that moves.

## The first attempt was right for a sphere and wrong for a crate

The shader already had the mechanism: `chatter` adds noise to the lighting term
before it is stepped. The roughcast was built as the same thing turned up, on the
reasoning that a rendered wall only shows where light rakes across it, and that
the hard steps would mask it everywhere else **for free** — no "only near the
edge" term to write and none to get wrong.

Rendered on five models and measured, it did almost nothing. Distinct colours over
the frame moved 1143 to 1226 across the entire useful range of the amount.

The reason is the geometry. **This work is flat shaded, so the lighting term is
constant across a face.** A perturbation therefore either flips a whole face from
lit to shadow or is clipped away entirely; there is no gradient across a face for
a grain to ride on. The reasoning was sound for a creature, which is curved, and
worthless for a crate, which is most of a town.

This is the same failure as decision 0060 — a shader reasoned about against one
kind of surface and applied to a library — caught earlier this time only because
the sweep was rendered on five different models instead of one.

## Decision

**The roughcast is a stipple drawn into the value, not a perturbation of the
light.** Two octaves of world-space noise, thresholded into specks rather than
left as a wash, darkening whatever tone the surface ended up with. That is what an
inker draws on a rendered wall, and it works on a flat face because it never asks
the lighting term for permission.

It is applied after the tones and before the terminator stroke, so it reads the
same in light and in shadow and the ink still lands on top of it. It keeps a share
of its strength on lit faces — not zero and not one: a rendered wall does show
most where the light rakes, but a lit face that went perfectly smooth would undo
the point on every south wall in the game.

World space throughout, for the reason decision 0063 already gives: this geometry
has no UVs worth the name, and a grain keyed on world position crosses the seam
between two tiles without showing it.

### The part that makes it robust

**A grain is faded out on its own screen footprint, analytically.** A grain a
centimetre across is a material at two metres and is pure noise at twenty: one
pixel spans several grains, nothing in it can be resolved, and sampling it once
per pixel gives a different answer every frame the camera moves. That crawl is
what gives a stylised surface away, and no amount of tuning fixes it.

So each octave is weighed against how much world one pixel covers here, and
removed before it can alias. Each fades towards its own mean rather than towards
zero, so a band on its way out lightens its contribution instead of shifting the
whole surface darker.

Measured on a wall filling the frame, mean local contrast by camera distance —
and the same mechanism is what made the first tuning invisible in the overworld,
see below:

```
1x   1.367
2x   1.398
4x   0.124
8x   0.000
16x  0.000
```

A distant wall goes **exactly** flat rather than grainy, which is also what a
drawing does: an illustrator stops rendering texture at distance rather than
drawing it smaller.

### A grain is sized for the camera, not for the hand

The first tuning was done on models filling the frame, and it was wrong. Put on
palm trees in the overworld it rendered as **nothing at all** — measured, zero
pixels changed — and the fade was working exactly as designed.

This game looks at the world from about seven metres, where one pixel covers
roughly seventeen millimetres. The grains had been set at thirty-eight and
thirteen millimetres, both under the two-samples-per-grain floor, so both were
correctly removed. **No amount would have brought them back**, which is why the
first report of it was "nothing changed at all".

The rule, and it is arithmetic rather than taste:

| grain vs pixel | what happens |
| --- | --- |
| five pixels or more per grain | a crisp speck |
| two to five | fading, softening |
| under two | removed — and it must be, or it crawls |

Ten and thirty per metre — ten and three centimetres — clear that camera with room
to spare. A scene the player walks close to wants both brought up. The consequence
is that **one grain size cannot be fine on a small prop and present at distance**:
at seven metres the finest speck that can exist is a centimetre or so, so a crate
reads as coarsely rendered rather than finely sanded. That is a property of the
camera, not of the shader.

Two bugs were found on the way there and both would have capped the layer at a
sixth of its strength whatever it was set to. The octaves were mixed before being
thresholded, so an octave collapsing towards its mean dragged the sum onto the
threshold and every pixel came back with half a speck; each is now cut separately
and the coverages are laid over one another. And value noise from eight hashes is
a bell too narrow to cut specks from — nearly all of it within a tenth of the
middle — so it is spread with one smoothstep before it is cut.

### Applied by hand, by name

Which models wear it is a comma-separated list of name fragments the author types,
matched by the same helper the grass uses. Empty by default, and that is the
point: this is a material somebody chooses for a model, not a look the palette
wears. The build reports every item it matched, because a fragment that matches
nothing looks exactly like a fragment that works until somebody looks at the tile.

## Consequences

**The creatures are untouched, and that was checked rather than assumed.** An
earlier version of this change routed `chatter` through the new fade and moved
0.19 % of the pixels on a creature — small, an improvement, and not what anybody
asked for. The chatter keeps its own unfaded path, documented as such, and a
textured sphere under the `comic-manga` preset still renders byte for byte
identical to before. Its latent crawl at a grazing angle is real, is recorded, and
is somebody's separate change.

**A fragment is greedy.** `Chest` also matches `Bone_ChestA`, and `Platform`
matches the ground tile a map is paved with. The report is the defence and there
is no second mechanism.

**Do not put it on a ground.** The fade means the grain exists near the camera and
is gone at distance. On a prop that is invisible — the whole object crosses one
band. On a floor of two and a half thousand identical cells it is a **disc of
texture centred on the player**, moving with them, which is worse than no texture
at all. The layer is for objects; the grain of decision 0063 is what a ground gets,
and it does not fade for exactly this reason.
