# 0073 — The species assets keep the names they arrived with

**Status:** Accepted
**Date:** 2026-09-12
**Relates to:** decision 0071; spec 16, sections 4 and 8; `content/README.md`

## Context

Decision 0071 settled the provenance of the models under `game/assets/species/`:
they are the project's own, on the maintainer's word, and they are committed.
It settled nothing about what they are *called*.

They are called what they were called when they arrived. 897 folders, `pm0001_00`
through `pm0892_00`, after dex numbers that are not ours. Textures named
`pm0624_00_pm0624_00_Body_Col.png` and `EyeOverlay_Eye.png`. Clips named
`ba20_buturi01`, in romanised Japanese.

CLAUDE.md forbids third-party **names** in the same breath as third-party assets
and code. So the tree is, on its face, in tension with the house rule, and the
question had to be answered rather than left to be rediscovered by the next
person to run `ls`.

The measured cost of answering it the other way:

| | Count |
|---|---:|
| Files under `game/assets/species/` | 10 665 |
| of which `.import` sidecars keyed by path | 4 504 |
| Scenes referencing a `res://` path by name | 897 |

And the name does not stop at the folder. It is the key the presentation
manifests are written against — `content/presentation/species_*.yaml`, the
generated payload beside them, `tools/presentation/build_species_manifests.gd`
and `game/presentation/creature/creature_view.gd` all carry it. A rename is not a
rename of files; it is a rename of files, of authored content, of a built
artefact and of runtime code, in one commit that cannot be split.

## Options rejected

**Rename everything onto ids of our own.** The reading of the house rule that
takes it literally. Rejected by the maintainer. The cost is the table above plus
the content and code keyed off the name, and it buys nothing: the strings are
internal, and an id of our own invented for the occasion would be a placeholder
too — swapping one placeholder for another at that price.

**Rename the folders only, and leave the textures and clips.** Cheaper, and
worse: two naming standards inside one folder, with no way to tell which files
had been through the rename. The codebase does not get a second way to do
something.

**Say nothing and let the guard's silence stand for consent.** What 0027's guard
did for provenance, nothing does for names. Rejected because the tension with
CLAUDE.md is real and visible in every path, and an unwritten answer is one that
gets reopened.

## Decision

**The names stay as they are**, at every level: folder, scene, mesh, texture and
clip.

**CLAUDE.md's ban on third-party names is read as a ban on third-party
identifiers being *names*.** The distinction is not invented here — it is already
the project's, in `content/README.md`: ids are structural placeholders, and
"names are part of the game's IP". `pm0892_00` is an identifier. It is not a
name, it names nothing a player meets, and the naming work that would give that
creature a name has not happened yet. When it does, it lands in content, where
names live, and not in a path.

This is also the reading spec 16 already took for the clips, deliberately and in
writing: section 4 keeps `ba20`/`ba21` because the source library turns out to
"carry a standard of its own, and a better one than a word", and maps it onto
our vocabulary rather than renaming into it. The `pm####_00` scheme is the same
kind of thing — a dense, collision-free, sorted key — kept for the same reason.

## Consequences

**The tension is documented, not removed.** Anyone reading CLAUDE.md against
`ls game/assets/species/` will see it; they are now pointed here. If the rule is
ever meant to cover identifiers too, that is a new decision superseding this one,
and its cost is the table above.

**A rename gets more expensive, not less**, as the presentation layer grows
against these keys. This entry is the record that the price was known when the
decision was taken.

**Nothing shipped is affected.** No string here reaches a player: the manifests
map these keys onto the vocabulary of spec 16 section 4 before anything is shown.
That seam is what keeps the swap of section 8 a content change rather than a port.
