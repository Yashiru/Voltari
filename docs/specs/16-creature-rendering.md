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
expressions, their drivers, and the frame windows that select them.

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

All of it is reattached when the scene enters the tree. This is the part of the
work that would otherwise be redone per creature by hand, and getting it into one
script is what made 860 models a batch rather than a project.

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

## 10. Testing obligations

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
- **The budget report is produced**, and its totals are non-zero — a reporter
  that silently measures nothing looks exactly like a roster under budget.
- **The report names a tier for every composition it measures.** A total with no
  budget beside it is the thing section 7 exists to avoid.
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

- **Characters, as opposed to creatures.** The player and NPCs need the same
  contract and a different vocabulary — walking has facings, a creature has none.
  Nothing here covers them.
- **What plays a companion clip.** The set is in the vocabulary because three
  quarters of the library carries it and it is content already paid for. No
  system asks for it yet: friendship, a party menu, a creature following the
  player are all unspecified.
- **How the runtime chooses among a slot's takes** — at random, in rotation, or
  weighted. Three landings exist; nothing yet says which one plays.
- **Locomotion transitions** (`fi30`, `fi31`) are extras today. Using them needs
  a movement system that knows it is starting or stopping, which spec 14's
  grid-locked step does not currently express.
- **Whether the style switcher ships.** The art direction is settled (section 9)
  and the runtime still carries several looks. Keeping the switcher costs a menu
  nobody outside the team needs; removing it costs the ability to compare. Which
  one ships is undecided.
- **Type colours** are provisional in the runtime and are a first reading rather
  than an art direction.
- **Level of detail and culling.** Untouched, and section 7 is what would tell us
  they are needed.
- **Shiny or alternate colourways**, which the source library carries as separate
  models and the manifest has no field for.
