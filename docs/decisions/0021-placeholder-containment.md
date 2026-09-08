# 0021 — Third-party placeholders stay on one machine

## Context

Gameplay needs creatures to test with long before the artist's models arrive.
The stand-ins are Pokémon GO assets: not ours, not licensed to us, and useful
only until they are replaced.

The risk is not deliberate misuse. It is a `git add -A`, a forgotten export
preset, a file committed months ago and removed since — history keeps it. Any
one of those turns a local testing convenience into distribution.

An earlier incident makes the point: 21 placeholder files, 1.7 MB, were
committed to a feature branch by a `git add .` that predated the ignore rule.
Ignoring a directory does nothing for files already tracked.

## Decision

Containment is enforced, at every point an asset could leave the machine, by one
check with several triggers.

`tools/placeholder-guard/placeholder-guard.mjs` refuses:

1. **the index** — anything staged under `game/assets/placeholders`
2. **the working tree** — anything git currently tracks there
3. **the whole history** — the path appearing in any commit, since a push
   carries them all
4. **export presets** — a preset that does not exclude the directory, because
   Godot follows scene dependencies and would compile a referenced placeholder
   into the `.pck` no matter what git thinks

It runs from three places, so no single bypass is enough:

- `tools/githooks/pre-commit` — via `core.hooksPath`, so the hooks are version
  controlled rather than living unversioned in `.git/hooks`
- `tools/githooks/pre-push` — the full check, because `--no-verify` skips the
  commit hook
- CI, on every push and pull request, with `fetch-depth: 0` — the layer nobody
  can skip

The asset clone is locked separately. It has a remote pointing at a public
repository, so its own pre-commit hook refuses every commit outright: it is a
read-only source, and nothing generated or downloaded there is committable.

Fetching a missing species is possible but never automatic. The pipeline prints
the command and stops; it does not reach for the network on its own.

## Options rejected

**Ignore rules alone.** They do not apply to tracked files, `git add -f` walks
past them, and they say nothing about what a build includes. This is what failed
before.

**A `.gitattributes` or LFS arrangement.** Solves storage, not distribution.

**Trusting the export preset alone.** It only exists once someone configures an
export, and a preset added later would silently miss the exclusion. The guard
fails on a preset that lacks it, so the omission is loud.

**Keeping the placeholders outside the project tree entirely**, loaded from an
absolute path. Safest, and rejected: it breaks dragging a creature into a scene,
which is the entire point of having them. Containment is enforced instead of
avoided.

## Consequence

A placeholder cannot be committed, pushed, or exported without deliberately
disabling several independent checks. If an export preset is added later without
the exclusion, CI fails rather than shipping the asset.

What this does not do is make the assets ours. They remain third-party, local,
and temporary — to be deleted once the real models land.
