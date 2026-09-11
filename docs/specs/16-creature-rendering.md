# 16 — Creature and character rendering

**Status:** Draft
**Depends on:** specs 09, 14; decisions 0020, 0026, 0027

Most specifications in this plan were written before the thing they describe.
This one is the exception: a working pipeline already takes a rigged FBX to a
scene that plays correctly in Godot, and it has been run over **860 models**.

So this document is largely **measured rather than designed**, and where it
departs from an earlier decision it is because the measurement disagreed.

Nothing here is derived from the placeholder assets themselves. The runtime
contract was established *against* them; it contains nothing *of* them.

---

## 1. What a creature is, at runtime

A `.tscn` with exactly three parts:

```
Node3D            the root, carrying the runtime script
└── Model         the .glb, instanced
```

Beside it, a **sidecar** describing what the glTF could not carry: face-sheet
expressions, their drivers, the frame windows that select them, and which
texture each surface wears in the second colouring.

A creature that has a second colouring also has a `shiny/` folder beside its
scene, one texture per surface.

**There is no per-creature code.** One script covers every creature, and a
creature that needed its own would be a creature the contract does not describe
— which is the signal to widen the contract, not to write a script.

## 2. What the runtime reattaches, and why it must

glTF carries geometry, skinning, animation curves and textures. It does not
carry:

- **which shader a surface wears** — the cartoon shading, its ink outline, the
  scrolling flame, the type-lit variants
- **per-clip loop modes** — glTF has no concept of a clip that should hold on its
  last frame
- **face-sheet expressions** — eyes and mouths are cells of an atlas, driven by a
  bone's position, and are keyframed rather than being a mood
- **which parts are stowed** — a part that should be hidden when nothing hides it
- **the second colouring** — a shiny wears different sheets on the same model

All of it is reattached when the scene enters the tree. This is the part of the
work that would otherwise be redone per creature by hand, and getting it into one
script is what made 860 models a batch rather than a project.

### The second colouring

**One model, a second set of sheets.** Not a second `.glb`: sixty megabytes of
geometry and animation do not need duplicating to change a hue, and two models
would drift apart the first time the export changed.

The textures sit in a `shiny/` folder beside the scene and the sidecar says which
belongs to which. **They are keyed on the surface, not on the source file**,
because by export time the two no longer line up — face sheets are copied opaque
and several surfaces can share one file, so the export writes one texture per
surface for exactly this reason.

A model without one ignores the flag entirely, which is what makes this safe to
carry on every creature whether or not it has a shiny.

**Nothing decides who is shiny.** Wearing the second colouring is a property of a
creature, not of a species, so it belongs in generation and in the save — and
neither has it. That gap is named in the open points rather than papered over
here.

## 3. Each creature brings its own rig

**This supersedes the archetype claim in decision 0020**, and the reason is worth
stating precisely because the original reasoning was not wrong so much as about
something else.

Decision 0020 said the production cost of rigged 3D only collapses with shared
archetype skeletons — biped, quadruped, serpentine, winged — and retargetable
animations. The pipeline uses none of that. Each model arrives with its own
skeleton, of its own size, and its animations are its own.

What made that workable is that **the placeholders arrive already rigged**: the
cost 0020 was worried about had already been paid by somebody else. That does not
transfer to the fakemon, whose rigs the artist authors.

The decision taken here is nevertheless the same shape as the pipeline: **one rig
per creature, no shared skeleton, no retargeting**, because the artist is
reproducing this contract exactly. The cost is real and is accepted rather than
argued away — see decision 0045 for what is being paid and what was rejected.

## 4. The animation vocabulary

**Fakemon use declared clip names**, checked against the model.

**A slot is a list, not a clip.** The library carries several takes for the same
meaning — three landings, two idles, three eats — and treating a slot as a single
clip would throw two thirds of them away. The runtime picks among a slot's takes;
a slot with one take is the ordinary case, not a special one.

### The three sets

| Set | Slots |
|-----|-------|
| **Battle** | `enter`, `idle`, `attack_physical`, `attack_special`, `hurt`, `faint` |
| **Field** | `field_idle`, `walk`, `run` |
| **Companion** | `companion_idle`, `happy`, `unhappy`, `eat` |

Three sets rather than one flat list, because they are asked for by different
parts of the game and a creature may legitimately have one set and not another —
a creature that never follows the player needs no companion clips.

**A slot enters the vocabulary when something asks for it.** The library carries
more than this and the extra clips are kept (below); they are not vocabulary
until a system names them, or every creature would owe a fallback for a clip
nothing plays.

### Mapping the placeholders onto it

The source library turns out to carry **a standard of its own**, and a better one
than a word: a two-letter context and a two-digit slot. `ba20` is the physical
attack whatever the rest of the name says.

| Ours | Source | Source word | Takes | Models |
|------|--------|-------------|-------|-------:|
| `enter` | `ba01` | land | A B C | 78% |
| `idle` | `ba10` | wait | A B | 78% |
| `attack_physical` | `ba20` | buturi (物理) | 01 02 | 69% |
| `attack_special` | `ba21` | tokusyu (特殊) | 01 02 03 | 76% |
| `hurt` | `ba30` | damage | S | 78% |
| `faint` | `ba41` | down | — | 72% |
| `field_idle` | `fi01` | wait | 01 02 | 32% |
| `walk` | `fi20` | walk | — | 76% |
| `run` | `fi21` | run | — | 76% |
| `companion_idle` | `kw01` | wait | — | 48% |
| `happy` | `kw32` | happy | A B C | 75% |
| `unhappy` | `kw30` | hate | — | 75% |
| `eat` | `kw50` | eat | A B C | 72% |

Measured across 569 animated models carrying 7,792 clips between them.

**The resolver takes two rules, in order: the code, then the word.** About 120
models carry no prefix at all — `waitA01`, `buturi01` — because two generations
of extraction coexist in the library. That is the trap that made an exact-match
list match nothing, silently, on the second model ever exported. Matching the
code first and the word second covers both, and neither rule is a guess about
the other.

For a fakemon the resolver does nothing: the manifest already names our clips.
The mapping is a placeholder-era bridge and should read as one.

### What is not an animation

Three kinds of name would be swallowed by a naive mapping, and each means
something else entirely:

- **Stow clips** — `HideLeftEar`, `HideRightEar`, `HideHair`. They drive the
  stowable-parts feature of section 2, not the animation player.
- **Effect tracks** — a clip suffixed `_FX` beside `attack_physical`,
  `attack_special` or `faint`. It plays *alongside* its slot, not instead of it.
- **Conversion noise** — `_FBX_OVERRIDE`, `_HAT_OVERRIDE`, `_1`, `_euler`,
  `_RemovedScale`, `_mtAdjust`, `_mtCleanup`. Stripped before anything is
  matched, or a duplicate take reads as a second variant.

### Nothing is dropped

**Every clip in a model is either mapped to a slot or recorded as a named
extra.** There is no third outcome, and the build says so.

Extras are the species' own: a mega-evolution appeal, an ear adjustment, a
sleeping loop, a locomotion transition. One or two models carry each, and a
vocabulary that grew a slot per exception would stop being a vocabulary. The
engine can play an extra by name; nothing asks for one automatically.

This is what makes the rule testable rather than aspirational. A clip that
matched nothing used to disappear without a word — which is precisely how the
first mapping attempt failed unnoticed.

### Looping

Loop mode follows from the slot: `idle`, `field_idle`, `companion_idle`, `walk`
and `run` loop; everything else holds on its last frame. Extras declare their own.

The placeholder era decided this with a substring test on `wait`, because take
names could not be trusted. That rule is what the bridge replaces, and it should
not outlive it.

## 5. The presentation manifest

`content/presentation/<species>.yaml`, one per species, the filename being the
identifier — the same rule as every other authored entity (decision 0025).

Kept out of the species file by decision 0026: content carries no presentation,
so that two species can share a rig and neither file learns about the other.

| Field | Meaning |
|-------|---------|
| `scene` | The `.tscn` to instance |
| `clips` | Slot to the **list of takes** in the model, or a declared fallback |
| `extras` | Clips the model carries that no slot claims, by name |
| `stow` | Clips that hide a part rather than animate one |
| `height` | Intended display height in metres |

```yaml
clips:
  idle: [ba10_waitA01, ba10_waitB01]
  attack_physical: [ba20_buturi01]
  hurt: use idle          # a declared fallback, not an omission
extras: [ba10_adjustear]
stow: [HideLeftEar, HideRightEar]
```

`clips` takes a list because a slot is a list (section 4). `extras` and `stow`
exist so that **every clip in the model appears somewhere in the manifest** —
which is what turns "nothing is dropped" from an intention into something the
build can check by counting.

**Validated in two stages**, because neither half can do the other's job:

- **the Node build** checks the manifest's shape and that the referenced files
  exist on disk
- **an engine-side meta-test** checks that the named clips are really in the
  model, and that the model carries nothing the manifest failed to mention —
  both of which need Godot to open it

This is the same split spec 09 makes for effect ids and spec 14 makes for map
scenes: each check lives where the thing being checked can actually be read.

## 6. Runtime code does not live in the placeholder quarantine

Decision 0027 keeps `game/assets/placeholders/` out of the index, out of the
history, and out of **every export preset**. It exists to contain third-party
models.

The runtime script and the shaders are not third-party. They are the project's
own, and they were quarantined by proximity rather than by nature — with a
consequence nobody chose: **an exported build would have nothing to display a
creature with.**

So they move out (decision 0046). What stays behind the guard is what the guard
was written for: the models, their textures, and their scenes.

## 7. The budget is measured, not enforced — and read against device tiers

The build reports triangles, texture sizes, bone counts and the roster totals. It
refuses nothing.

**A raw total tells nobody whether the game runs.** So the report is read against
named device tiers, and says which of them a scene fits:

**A shiny is a package cost, not a scene cost.** It replaces a surface's texture
rather than adding one, so a shiny creature costs a scene exactly what a normal
one does — and every shiny in the game ships whether it is ever worn. The report
keeps the two apart, because folding them together answers neither question.

| Tier | Stands for | Triangles on screen | Texture memory |
|------|-----------|--------------------:|---------------:|
| `low` | a five-year-old budget phone | 150,000 | 256 MB |
| `mid` | the median phone in use | 400,000 | 512 MB |
| `high` | current flagship | 1,000,000 | 1 GB |

A battle shows two to four creatures plus terrain, so the per-creature figure
that matters is the total divided by that, not the model on its own.

**These numbers are provisional and are marked as such in the tool.** Nobody has
profiled this game on any device, so they are informed guesses, and an informed
guess presented as a frame rate would be worse than no number at all. What the
report gives honestly is a *comparison against a stated budget*, not a
prediction — "this composition is at 140% of `mid`" is a fact about the assets;
"this will run at 42 fps" would not be.

The tiers live in one file so that the afternoon somebody runs the game on a real
mid-range phone, the guesses are replaced by measurements in one place and every
past report becomes re-readable.

The risk stands and is worth naming plainly: **a number nobody is obliged to
respect is a number nobody respects.** What makes it survivable is that the
report is cumulative, so the trend is visible long before a device says anything.
If the trend is ignored, the ceiling is one line in the build and decision 0048
is what should be revisited.

## 8. Placeholders and the swap

A placeholder and a fakemon differ in exactly one way: **provenance**. Same scene
shape, same script, same manifest, same vocabulary — which is what makes the swap
a content change rather than a port.

The guard of decision 0027 is what keeps that from being an accident waiting to
happen, and it stays exactly as strict as it is. Moving the runtime code out
(section 6) narrows what it guards; it does not weaken it.

## 9. The art direction is comic-manga

**The look is the `comic` shader**, with its ink outline. That settles what was
open: the runtime carries several shading styles, and this is the one the game
wears.

It is recorded here rather than left in a settings file because it constrains
everything downstream — a cartoon shader wants flat, saturated albedo and clean
silhouettes, which is a brief for the artist and not a runtime toggle. Named
variations of it (`comic-noir` and the like) are sets of numbers for the same
shader, not separate looks.

### It is worn by every surface, not only by creatures

**Settled by decision 0062.** The look was applied to creatures alone, so a
creature stood on ground drawn by a different set of rules — a printed drawing on
a photograph. It now covers the tiles, the props, the grass and the character.

The look itself lives once, in `comic_look.gdshaderinc`. Two shaders include it:
`comic.gdshader` for everything still, and `grass_parting.gdshader` for grass,
which needs `cull_disabled` and carries the wind of decisions 0059 to 0061. **The
wind is deliberately not shared** — grass moves and almost nothing else does.

Three consequences are worth knowing before writing anything that draws:

- **The project has no lights and cannot have any.** The look is `unshaded` and
  lights itself from `light_direction`; the screentone has to be laid out in
  screen space against the same value that picks the tone, which Godot's `light()`
  stage cannot see. A `DirectionalLight3D` added to a scene will do nothing.
- **A subject is relit, a set is not.** `key_follows_camera` is 0.7 on creatures
  so their form always reads, and 0 on the world so the shading does not slide
  across the terrain as the player turns.
- **Switching the look is a rebuild for the map.** The tile library bakes the
  style's uniforms into the `MeshLibrary`; creatures and the character read the
  style file when they load. All three read the same two files.

**Known limitation.** A creature keeps screentone off its face by raising
`face_flat` on the surfaces that carry the eye and mouth sheets. The character's
face is painted into its body texture and has no surface of its own, so the coarse
screen falls across it wherever the face is in shadow. Visible on a close-up, not
at the distance the overworld camera sits. Fixing it means either a separate face
surface on the model or no tone on the character at all, and that is an art
decision, not a runtime one.

## 10. A creature is never still

**Settled by decision 0055**, which closes the open point about how the runtime
chooses among a slot's takes.

A clip that ends hands back to the **idle**, and the idle hands back to itself.
Nothing in the runtime knows it is looping: it plays the idle when the model
appears, and again whenever anything finishes. A creature frozen in its rest pose
between attacks does not read as a still frame — it reads as a crash.

A slot with several takes reaches past the first about **one time in four**.
Weighted rather than uniform or in rotation: two idles alternating is a two-beat
rhythm a viewer sees within seconds, and the point of a second idle is that it is
not expected.

The randomness is **its own source** and never one of the decision vocabularies
(decisions 0010 and 0029). It follows that a screen is no longer reproducible
frame for frame. What is asserted instead is the policy — the first take
dominates, a second take is reached at all — which is what the suite tests.

**A model is scaled to the `height` its manifest declares** (section 6). The field
was loaded, documented and read by nobody, so creatures were drawn at whatever
their exporter produced — half a metre against a metre and a half — which makes
framing a battle impossible.

## 11. Characters walk, and creatures do not

**Settled by decision 0057**, which closes the open point about characters.

A second runtime beside the creature one, not a shared base: what they have in
common is "instance a model and play a clip", and everything else differs.

- **A character turns** towards its grid facing rather than snapping to it.
- **Its legs answer to the ground.** A creature's clip is a reaction to an event;
  a character's is a function of a speed.
- **It settles.** Two steps in a row are separated by a frame at zero speed, and
  without a grace the legs flicker on every cell boundary.

**The world moves at the speed the animation was authored for, and that speed is
measured.** An in-place clip carries a compressed stride and an honest cadence,
so the speed comes from the cadence and a step length proportional to height.
`tools/characters/measure_gaits.gd` prints it; the runtime uses it; nobody has to
believe a number.

How long a cell takes is `cell width / ground speed`, with the width read from
the map's own grid — so a map on a finer grid is crossed at the same speed rather
than at the same rate.

**A character is not scaled.** A creature's size is a design fact its manifest
declares; a person's is not, and 1.7 m with feet at the origin is already a
person on a two-metre grid.

**Clips loop because the `.import` says so**, not because the runtime patches a
shared resource on every load.

## 12. The world's grass

The first thing in this project that is **judged by looking**. No assertion
distinguishes grass that moves from grass that moves well, so the evidence is a
contact sheet rather than a test (decisions 0059, 0060 and 0061).

`game/presentation/world/grass_parting.gdshader` does two small things and holds
no state at all.

**Wind.** **One wind for the whole world** (decision 0061). Two travelling waves
summed — a long, slow one that is the gust crossing the field, and a shorter one
at another speed so the sum is not a sine — under a slow global breath. Both are
functions of world position and time alone, which is what makes a gust *travel*:
a blade's phase comes from where it stands, so neighbours are in step and distant
grass is not.

**Nothing varies per tuft.** No phase of its own, no stiffness of its own, no
rotation and no size. A hundred independent clocks cannot add up to one air mass
however slowly each of them ticks — an earlier version gave every tuft all four
and it read as elastic and random rather than as wind.

**A jostle.** Stepping into a cell sets that cell swinging once, and it settles
in about three quarters of a second. Two cells may ring at a time — the one being
stood in and the one just left — because a cell is crossed in about half a second
and one slot would cut every swing off mid-air.

**A tuft never changes shape.** Every blade of a cell leans the same way by the
same amount. An earlier version pushed blades apart radially and it read as
damage rather than as somebody passing (decision 0060).

### Where the state lives

The shader is a function of the moment: two cells and how long ago each was
entered. Everything with a past is in `grass_field.gd`, and there is very little
of it — a jostle is one shot, nothing accumulates, and nothing is recorded about
where anybody has been.

**How far a jostle reaches comes from the grid**, read off the map's own cell
width, so a map painted on a finer grid rings one of its own cells rather than a
metre's worth of somebody else's.

### What is measured, and what is not

Tested: that a step starts a swing, that a swing ends, that the cell just left
keeps ringing, that the reach follows the grid, and that a warp leaves nothing
ringing on the map arrived at.

Looked at: everything else, with `tools/grass/preview.gd`, which takes the item
name as an argument. **One asset is not evidence** — the version this replaced
was tuned against a single sparse tile and tore a dense one.

**Not measured at all: the cost on a phone.** 323,200 vertices cost 5.9 ms a
frame on the desktop GPU this was written on. The project targets the Mobile
renderer and this has never run on one; `tools/budget/` covers assets and not
shaders.

## 13. Testing obligations

- **Every manifest loads** into its typed form, and every path it names exists.
- **Every clip a manifest declares is really in its model** — the engine-side
  meta-test, which is the only place that can open a `.glb`.
- **A missing clip with no declared fallback is refused**, proven by a fixture
  built to fail.
- **A declared fallback is accepted**, and resolves to the clip it names.
- **The vocabulary is complete**: every name the runtime can ask for is one the
  manifest schema knows, checked by a meta-test rather than by reading both
  lists.
- **A creature scene instances and reaches its rest state** without a script
  error, for every committed creature.
- **A clip that ends hands back to the idle**, and the idle to itself, so a
  creature is never left standing in its rest pose (section 10).
- **The variant take is the exception and is reached at all** — the policy, not
  a frame, since decision 0055 makes a frame irreproducible on purpose.
- **A model ends up the height its manifest declares**, whatever its own is.
- **A character runs while the ground moves and settles to its idle when it
  stops**, without dropping to the idle between two chained steps.
- **A character turns rather than snapping**, arrives, and never overshoots.
- **Every clip the gait vocabulary can ask for is in the model**, and every one
  of them loops — checked against each other rather than by reading two lists.
- **The budget report is produced**, and its totals are non-zero — a reporter
  that silently measures nothing looks exactly like a roster under budget.
- **The report names a tier for every composition it measures.** A total with no
  budget beside it is the thing section 7 exists to avoid.
- **The second colouring is counted apart from the scene budget**, because it
  replaces a texture rather than adding one. Counting it in would overstate every
  scene; leaving it out entirely would understate the download by more than half.
- **The placeholder mapping resolves by code before word**, proven on both
  shapes: a prefixed name and a bare one. Getting the order wrong still resolves
  most clips, which is what makes it worth a test rather than a reading.
- **Every clip of every model is accounted for** — mapped to a slot or recorded
  as a named extra, with no third outcome. Run over the whole library, this is
  the obligation that would have caught the original silent failure.
- **A slot keeps all its takes.** Three landings map to three, not to one, and a
  model with two idles does not lose the second.
- **Conversion noise is stripped before matching**, so `landA01` and
  `landA01_1` are one take rather than two.
- **Stow clips and `_FX` tracks never reach the animation vocabulary**, proven
  on a model that carries both.

## Open points

- **NPCs.** Section 11 covers the player. An NPC needs the same runtime and a way
  to be placed and scripted, which is spec 15's business and not written.
- **What plays a companion clip.** The set is in the vocabulary because three
  quarters of the library carries it and it is content already paid for. No
  system asks for it yet: friendship, a party menu, a creature following the
  player are all unspecified.
- **Which take a *non-idle* slot plays**, for a creature that has several. The
  idle is settled (section 10) and nothing else has more than one take on any
  model there is, so the rule is written where it is exercised and no further.
- **Locomotion transitions** (`fi30`, `fi31`) are extras today. Using them needs
  a movement system that knows it is starting or stopping, which spec 14's
  grid-locked step does not currently express.
- **Whether the style switcher ships.** The art direction is settled (section 9)
  and the runtime still carries several looks. Keeping the switcher costs a menu
  nobody outside the team needs; removing it costs the ability to compare. Which
  one ships is undecided.
- **The grass shader on a phone.** Section 12's numbers are a desktop
  measurement. Whether the per-vertex matrix inverse is affordable on the Mobile
  renderer is unknown, and `tools/budget/` does not cover shaders.
- **Whether the world gets one art shader.** The grass shader is deliberately
  isolated: the comic-manga direction of section 9 is settled for creatures and
  nothing is settled for the world. Folding this into a world shader, or leaving
  it beside one, is undecided.
- **Type colours** are provisional in the runtime and are a first reading rather
  than an art direction.
- **Level of detail and culling.** Untouched, and section 7 is what would tell us
  they are needed.
- **What makes a creature shiny.** The rendering side is settled (section 2);
  what is missing is upstream. It is a draw at birth, so the generation
  vocabulary needs a question it has not got (spec 10, decision 0029), and a
  creature needs a field the save carries. Neither exists, and inventing either
  here would be spec 16 deciding spec 10's business.
- **Alternate forms** — the library carries them as separate models with their
  own ids, which the manifest already handles as separate species. Whether
  Voltari wants forms at all is undecided.
