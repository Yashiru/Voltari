# 0062 — One look, every surface

**Status:** Accepted
**Date:** 2026-09-11
**Recorded in:** spec 16, sections 9 and 12

## Context

Spec 16 section 9 settled the art direction as `comic`, and the runtime applied it
to **creatures only**. Everything else on screen was drawn by something that had
never heard of it:

| what | what it wore |
| --- | --- |
| creatures | `comic.gdshader`, unshaded, lighting itself |
| grass | `grass_parting.gdshader`, **lit** — `diffuse_burley`, roughness, backlight |
| tiles and props | the `StandardMaterial3D` the FBX imported, flat |
| the character | the same, nothing stylised |

A creature standing on that ground was a printed drawing on a photograph. The
maintainer asked for the look to cover the whole game.

There are two credible places to compute a stylised look, and the choice is
load-bearing.

## Options rejected

**A screen-space post-process pass.** One `CompositorEffect` over the viewport:
halftone keyed on luminance, ink from depth and normal edge detection. It covers
literally everything, including anything nobody has dressed, and touches no
material.

Rejected because it **cannot reuse the look that exists**. The terminator, the
shadow hue, the two screens and the terminator stroke are computed in lighting
space — from `dot(N, L)`, before anything is resolved to a pixel. A post pass has
only the final luminance and would have to re-derive all four from it. That is a
second implementation of one look, the presets would drive only half of it, and
the two halves would disagree the first time either was tuned.

**A separate world shader carrying its own copy of the look.** Zero risk to the
creature shader and to the quarantined asset pipeline that copies it. Rejected for
the same reason at smaller scale: the maths would exist twice, and a terminator
tuned in one file and not the other puts the creatures and the ground in different
books.

**One shader for every surface, wind included.** Maximum unity, one file.
Rejected because `render_mode` is per shader and not per material: a blade of
grass is a card and must draw from both sides, so the whole world would have to
pay `cull_disabled` — backface fill on ninety-two opaque models to serve the one
item that needs it. The maintainer also pointed out the decisive thing: **the wind
applies to almost nothing.** A look shared by every surface in the game has no
business carrying a vertex stage twelve items use.

## Decision

**The look lives once, in `comic_look.gdshaderinc`. Movement does not.**

The include holds the uniforms, the helpers and two functions — `comic_paint` for
the flat fill, `comic_shade` for the print. Three shaders include it:

- `comic.gdshader` — creatures, tiles, props, the character. `cull_back`.
- `grass_parting.gdshader` — grass, and grass alone. `cull_disabled`, plus the
  wind and the jostle that decisions 0059 to 0061 settled.

Grass keeps of its own colour only what follows the blade: darker in the thatch,
warmer at the tip. The shared look has no idea a blade has a bottom and a top.

Two shaders and not one because of `render_mode`, and that is the whole reason. If
Godot ever allows a per-material cull, they become one file.

### A flat colour joins the texture

The include declares `albedo` beside `albedo_tex`, and `albedo_tex` is
`hint_default_white`. A creature has a texture and no colour; a world model has a
colour and no texture; the product covers both with no flag to say which, and a
creature is bit-for-bit unaffected by the addition.

### A subject is relit, a set is not

`key_follows_camera` stays at 0.7 on creatures and is **0 on the world**. A
creature is a subject and gets relit every panel so its form always reads. The
ground is not a subject: a key that swung with the camera would slide the shading
across the terrain as the player turned, which is the one thing a set must never
do. `shape_round` is likewise 0 on the world and on the character — a wall is
genuinely flat, and a person is not an ovoid.

## Consequences

**The project has no lights at all, and cannot have any.** `unshaded` is not
optional for this look: the screentone must be laid out in screen space against
the same value that picks the tone, and Godot's `light()` stage runs once per light
with no screen coordinates in scope. Every surface now lights itself from
`light_direction`. The inert `DirectionalLight3D` in `battle_screen.tscn` was
removed rather than left as a trap for the next person; the grass lost its
`translucency`, which was a backlight nothing computes any more.

**Switching the look is a rebuild for the map and a restart for the rest.** The
tile library bakes the style's uniforms into the `MeshLibrary` because that is
already the one thing that writes world materials. The alternative is a runtime
that walks every material in a loaded map, which would be a second owner of the
world's materials for a setting that changes once a month. The character and the
creatures read the style file when they load. All three read **the same two
files**, so they agree; the map simply learns later.

**The world follows only the comic family.** A style naming a different shader —
`toon`, `vinyl`, `bd` — leaves the world on plain `comic` rather than dressing it
in a shader that has no world variant. The editor picker still offers them, for
creatures.

**World props have no silhouette ink.** A creature gets one from the separate
`outline.gdshader` pass hung on its material. Ninety-two library items each
growing a second pass is a cost nobody has measured and nobody asked for, so props
carry the terminator stroke and stop there.

**The include must reach the quarantine.** `comic.gdshader` exists in two copies —
the tracked one and a copy the out-of-repo asset pipeline writes into
`game/assets/species/_shared/` (decision 0027), which a standalone flat viewer
also uses. A relative include resolves in all three places only if the file sits
beside the shader, which is why it lives at `game/presentation/creature/` and the
world shaders reach it by absolute path. **The pipeline's copy step must carry
`*.gdshaderinc`**, or the quarantined viewer stops compiling the next time it runs.
The address says `creature`; the contents are the whole game's, and the include
says so at the top.
