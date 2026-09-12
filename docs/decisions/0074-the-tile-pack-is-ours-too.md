# 0074 — The tile pack is licensed, and the quarantine ends

**Status:** Accepted
**Date:** 2026-09-12
**Supersedes:** decision 0027, entirely — with 0071 it leaves nothing quarantined
**Recorded in:** CLAUDE.md, `docs/authoring-maps.md`

## Context

Decision 0027 kept third-party stand-ins out of the repository, and decision 0071
lifted half of it: the creature models are the project's own and are committed
through LFS. What was left was the tile pack — `game/assets/species/brawl_arena/`
and the `.meshlib` built from it — held out on the reading that a licence to use
an asset in a game is not a licence to redistribute it, and that a repository
redistributes.

`tools/species-guard/species-guard.mjs` enforced that: it refused the path in the
index, in the tree, in the whole history and in every export preset, from a
pre-commit hook, a pre-push hook and a CI job.

## The fact this rests on

**The maintainer states that every asset in the repository is licensed for
commercial use and safe to redistribute, the tile pack included.** That was said
after the distinction between "licensed to use in a game" and "licensed to
redistribute" was put to them explicitly, and after being told that a commit is
permanent in history.

It is recorded here in those terms, the way decision 0027 recorded its own
exception, because it is the load-bearing fact and it is not one the repository
can check for itself. Nothing in the tooling can verify a licence; what the
journal can do is say who decided, when, and on what basis.

## Decision

**The quarantine ends.** The pack and its `.meshlib` are committed through LFS,
the ignore rules go, and `species-guard` is deleted along with its hooks and its
CI job.

**The clean-room rule is untouched.** CLAUDE.md still says no third-party code
enters this repository and that reference implementations are read as behavioural
documentation only. What changes is that these particular assets are not
third-party in the sense that mattered — not that the rule has softened.

## Options rejected

**Keeping the guard pointed at nothing.** It would still run on every commit and
every push, cost a Node startup each time, and refuse a path that is now
deliberately full. A guard whose answer is always yes teaches people to ignore
guards.

**Keeping the ignore rules and committing nothing**, on the grounds that 53 MB is
large. Rejected because the size is the smaller half of the question and the
first half is already answered: a clone currently gets maps with no library, so
the world is walkable and completely invisible, and every screenshot, every
visual judgement and every CI run that might have looked at a map has been
impossible for anyone but one machine.

**Committing the pack and keeping the guard for future packs.** Rejected as a
guard for a rule nobody has stated. The next third-party pack, if there is one,
gets its own decision and its own mechanism; a guard aimed at one historical
path is not that mechanism.

## Consequences

**A clone now renders.** The maps become visible in CI and on any machine, which
is what makes a golden-map test worth writing and what lets the map editor's new
overlay be judged by looking rather than by assertion.

**The content build stops pretending.** `existsSince` accepted any path under
`game/assets/species/` without checking, on the stated grounds that decision 0027
put those files on exactly one machine so a check would fail on every clone but
one. That is no longer true, so the check becomes real and a renamed species
scene is caught like any other.

**The repository grows by the pack**, permanently and in LFS. That is the part
that cannot be undone, and it is why the fact above is recorded rather than
assumed.

**Decision 0027 is fully superseded and marked as such.** Its history stays: the
incident it records — 21 species files committed by a `git add .` that predated
the ignore rule — is the reason `git add -A` at the repository root is still a
bad habit, whatever is or is not licensed.
