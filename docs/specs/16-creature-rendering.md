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

The placeholder era does it differently and cannot be fixed: take names differ
between source models — one names a clip `waitA01`, another names the same thing
`ba10_waitA01` — so loop selection is a **substring test on `wait`**. An
exact-match list was tried first and matched nothing, silently, on the second
model exported.

That substring rule stays for placeholders and is named for what it is: a
workaround for names nobody controlled. It is not the convention.

**A clip in the vocabulary that a creature has not got is refused at build,
unless the manifest declares a fallback** — `hurt: use idle` is accepted because
somebody wrote it; silence is not.

The distinction is between an author's decision and an omission. A missing faint
animation discovered in front of a player is the failure; a hard refusal instead
would mean no creature can enter the repository until it is fully animated, and
most of a roster is half-animated for months.

## 5. The presentation manifest

`content/presentation/<species>.yaml`, one per species, the filename being the
identifier — the same rule as every other authored entity (decision 0025).

Kept out of the species file by decision 0026: content carries no presentation,
so that two species can share a rig and neither file learns about the other.

| Field | Meaning |
|-------|---------|
| `scene` | The `.tscn` to instance |
| `clips` | Vocabulary name to the clip in the model, or a declared fallback |
| `height` | Intended display height in metres |

**Validated in two stages**, because neither half can do the other's job:

- **the Node build** checks the manifest's shape and that the referenced files
  exist on disk
- **an engine-side meta-test** checks that the named clips are really in the
  model, which needs Godot to open it

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

## 7. The budget is measured, not enforced

The build reports triangles, texture sizes, bone counts and the roster totals. It
refuses nothing.

This follows the standing rule that performance is measured rather than asserted,
and it carries a risk worth naming plainly: **a number nobody is obliged to
respect is a number nobody respects.** The failure is cumulative and only appears
with the full roster on a real device, at which point the fix is re-authoring
assets rather than changing code.

What makes it acceptable is that the report is per-asset *and* cumulative, so the
trend is visible long before the device says anything. If it turns out not to be
enough, the ceiling is one line in the build and this section is what should be
revisited.

## 8. Placeholders and the swap

A placeholder and a fakemon differ in exactly one way: **provenance**. Same scene
shape, same script, same manifest, same vocabulary — which is what makes the swap
a content change rather than a port.

The guard of decision 0027 is what keeps that from being an accident waiting to
happen, and it stays exactly as strict as it is. Moving the runtime code out
(section 6) narrows what it guards; it does not weaken it.

## 9. Testing obligations

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

## Open points

- **Characters, as opposed to creatures.** The player and NPCs need the same
  contract and a different vocabulary — walking has facings, a creature has none.
  Nothing here covers them.
- **The style system.** The runtime carries several looks and a per-roster
  setting. It works; what it should be for the real art direction is a design
  question nobody has answered.
- **Type colours** are provisional in the runtime and are a first reading rather
  than an art direction.
- **Level of detail and culling.** Untouched, and section 7 is what would tell us
  they are needed.
- **Shiny or alternate colourways**, which the source library carries as separate
  models and the manifest has no field for.
