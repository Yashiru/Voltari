# 0069 — One pipeline, five quantisers

**Status:** Accepted
**Date:** 2026-09-11
**Supersedes the shape of:** decision 0074 (six looks in one shader)
**Recorded in:** spec 16, section 9

## Context

The maintainer asked four questions in a row, and they were one question:

> Why do all the shaders have the same settings available when they have nothing
> to do with each other? Why is there an `ink` setting for shaders that are not
> supposed to have any ink? Nothing about these shaders is logical.

Decision 0074 put six looks into one shader, which was right, and left them as six
strangers sharing an address. Each kept the vocabulary it had been written with, so
one file declared:

- four shadow tints — `shadow_hue`, `toon_shadow_tint`, `bd_shadow_tint`,
  `vinyl_shadow_hue` — plus a fifth depth of its own in `typelit`
- four wraps, three sky gradients, two halftones, two creases, two rims
- a `terminator` at 0.14 on a raw dot product and a `bd_terminator` at 0.46 on a
  remapped one. **The same word, two scales.**
- `ink`, which is not a line, draws nothing, and is a ceiling on the paint

And the editor panel that drove all of this knew exactly one look's half of it: of
its eighteen sliders, **thirteen did nothing on five looks out of six.** They moved,
they wrote a value onto the material, and no branch of the shader ever read it.

## What was actually wrong

Four of the seven findings were visible on screen, not merely untidy.

**Three looks went to pure black in a thrown shadow.** Each ported look multiplied
its result by the shadow term. `toon_wrap` exists precisely so that an unlit side
keeps its colour, and multiplying by zero takes it to black anyway — so the one
feature the look was built around was cancelled by the shadow that decision 0073
had just bought.

**`face_flat` was honoured by two looks out of six.** Wearing `bd` laid a halftone
across the whites of the eyes; wearing `toon` drew a rim around them.

**Five looks could not be saved.** They were shaders rather than presets, so the
panel's **Keep** refused them — the one look you could not write down was the one
you had just spent an hour tuning.

**And switching looks accumulated.** `Look.wear` pushed a preset's values and never
cleared anything, so a look whose preset was silent about a value inherited it. Go
`comic-sunday` → `toon` → back and the saturation is still at 1.55 with nothing in
any file saying so. The maintainer found this by playing with the picker, one turn
after decision 0075 had cured the same symptom from a different cause.

A fifth thing was found on the way: `key_follows_camera` and six `stucco_*` values
were **deleted from the shader** during the lit rework, and two scripts went on
setting them for four commits — one of them a feature being actively refined.

## Decision

**One pipeline. The only thing a look changes is how the light term is stepped.**

```
paint    →  tones  →  quantise  →  thrown  →  screen  →  ink  →  add
```

Every stage is shared by every look. `quantise` is five branches:

| quantiser | what it does | the looks that are it |
| --- | --- | --- |
| `comic` | two steps and a core | `comic` and its five variants |
| `bands` | N soft-edged steps | `toon` |
| `step` | one hard step at the terminator | `bd`, `typelit` |
| `smooth` | nothing | `vinyl` |
| `ramp` | a strip lookup | `ramp` |

Each is handed the same tones and answers the same two questions besides its
colour: what this surface looks like with the key fully blocked, and how lit it
ended up. Everything else — the sky gradient, the screen, the crease, the rim, the
highlight, the cast shadow, the chatter — is a stage, and is the same for all five.

**A look is a preset.** `toon`, `bd`, `vinyl`, `ramp` and `typelit` are entries in
`style_presets.json` like `comic-noir` always was. There is no longer such a thing
as a look that is only a shader, which is what made those five unsaveable.

**One name per question**, so 67 values where there were far more, and four of them
local to one quantiser: `bands`, `core_level`, `core_extra`, `ramp_row`.

**`ink` is `fill_ceiling`.** It is a ceiling on the paint and always was. The real
ink is `ink_colour`, and every dot, speck and stroke in the file now mixes towards
it. Black by default, where that mix is exactly the multiply each of those stages
did by hand — so `comic` comes out unchanged.

## Consequences

**The honest answer to the question turned out to be the opposite of hiding rows.**
The panel could have been taught which of the six vocabularies to show. Instead the
six became one, so a control now means the same thing in every look and offering it
everywhere is correct rather than a lie. Only four rows are hidden, and they are
hidden because they genuinely belong to one quantiser.

**`Look.wear` resets the whole vocabulary to the shader's defaults before applying
a preset.** A preset is read as complete. That is the fix for the accumulation, and
it is why every preset now spells out its zeros.

**Two defects were found by rendering the result**, neither of which was in the
brief:

- *The shadow terminator problem.* A surface turning away from the key is where the
  shadow map's depth test is most grazing and least reliable, so it returns a
  speckle along the terminator — and `cast_hardness` snapped that speckle into hard
  teeth. Measured: with the shadow map off the same edge is clean. `cast_grip`
  releases the thrown shadow as the term falls to the terminator, which is also
  what an inker does — nobody draws a cast shadow onto a face already in shade.
- *A highlight is a mark of a form.* Ungated, `toon`'s stepped specular bloomed
  across the ground plane as a metre-wide pale disc. It is gated by how fast the
  normal is turning, exactly as the rim already was, and for the same stated
  reason. Neither showed while these were creature shaders, because a creature has
  no ground plane in it.

**The vocabulary is checked, not trusted.** `tests/presentation/look_vocabulary_test.gd`
parses the include and asserts that its uniforms are exactly what `Look` classifies,
that no preset names anything that is not a value, and that every preset resolves to
a quantiser that exists. The `stucco_*` regression above is the reason: four
commits of a script setting names the shader had dropped, in silence, because
`set_shader_parameter` accepts anything.

**Measured after:** all eight looks render with **zero clipped channels**, and the
brightest pixel in each is the paper itself — nothing in the scene is brighter than
the page it is printed on.

**What this costs.** The comic presets' `terminator`, `core_level` and the three
reach values were converted onto the shared scale, arithmetically; they are the same
looks. A tile library built before this carries the old names, so its baked `ink`
is ignored and `fill_ceiling` falls back to its default — `Look.wear` overrides both
at map entry, so the only consequence is that a rebuild is worth doing when
convenient.
