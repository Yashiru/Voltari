# 0071 — The creature models are ours, and are committed through LFS

**Status:** Accepted
**Date:** 2026-09-11
**Supersedes:** decision 0027, for the creature models only
**Recorded in:** spec 16, section 6

## Context

Decision 0027 quarantined the creature stand-ins because they were Pokémon GO
assets — not ours, not licensed to us. The guard it installed refuses them in the
index, the tree, the whole history and every export preset, and it has been doing
so since.

The maintainer reports that the models under `game/assets/species/` are now the
project's own, and asked for them to be committed. Provenance is a fact about the
work, not about the repository: nothing in a file says who made it, so this rests
on the maintainer's word, which is where it has to rest.

That half of 0027 no longer applies. The other half still does.

## Decision

**The 897 creature models are committed**, with their scenes, clips and textures
— 10 668 files, 1.7 GB.

**Through Git LFS.** A `.glb` and a `.png` are already compressed, so a delta
against a previous version buys nothing and an ordinary commit of one stores the
whole file again, permanently. A pointer is 130 bytes. 4 504 binaries go to LFS;
the 6 164 `.tscn`, `.import` and `.json` beside them are text and stay ordinary
blobs, where git's compression does work.

Every LFS pattern carries `-text`. A `.glb` put through line ending
normalisation is a corrupt `.glb`, and it would be corrupt only on the machine
that checked it out — which is the worst shape a defect can have.

**The tile pack stays quarantined.** `brawl_arena/` is two Unity Asset Store
packs, and the `.meshlib` is built from them and so derived from them. A licence
to use an asset in a game is not a licence to redistribute the asset, and a
repository redistributes. The guard keeps its job and its name; only its target
narrows, from `game/assets/species` to those two paths.

## Consequences

**A clone is now 1.7 GB and needs `git lfs` installed.** Without it, the working
tree fills with 130-byte pointer files and Godot imports none of them. That is a
new prerequisite for the project and it belongs beside Godot 4.7.2 and Node 22.

**A map painted from the tile pack still works for a clone**, unchanged from
0027: a `GridMap` keeps its cells with no mesh library at all, so the world stays
exactly as walkable as it was painted and turns invisible.

**Three binaries predate `.gitattributes`** — `main-char.glb`, the model fixture
and the starter tile library — and were committed as ordinary blobs. Their
current versions are now pointers; the old blobs remain in history. Nothing has
been pushed, so `git lfs migrate import` would still clean that up if the history
is ever worth rewriting.

**Renaming the quarantine to `game/assets/species/` happened just before this**
and is unrelated to it: it was a vocabulary change, and it is what makes the
folder's name still true now that most of it is not quarantined at all.
