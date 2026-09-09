# 0047 — A missing animation needs a declared fallback, not silence

**Status:** Accepted
**Date:** 2026-09-09
**Recorded in:** spec 16, section 4

## Context

The runtime asks for animations by name: idle, attack, hurt, faint. A creature
that has not got one has to do something.

Most of a roster is half-animated for months. That is not a failure state, it is
what production looks like.

## Decision

**A vocabulary name a creature has not got is refused at build, unless the
manifest declares a fallback** — `hurt: use idle` is accepted; silence is not.

The placeholder era keeps its own rule and is not covered by this: source take
names differ between models — `waitA01` on one, `ba10_waitA01` on another — so
loop selection there is a substring test on `wait`. An exact-match list was tried
first and matched nothing at all, silently, on the second model exported. That
rule is a workaround for names nobody controlled, and spec 16 says so rather than
letting it read as the convention.

## Options rejected

**Refusing outright.** Spec 09's rule with no accommodation: malformed content is
the developer's problem, and the build is where a human is watching. Consistent,
and it would guarantee every committed creature is complete.

Rejected on what it does to production. No creature could enter the repository
until fully animated, so the roster would arrive in one late lump and nothing
could be played with in the meantime — which is the opposite of why the
placeholders exist at all.

**Falling back automatically and silently**, idle standing in for whatever is
missing. Nothing ever blocks.

Rejected because nobody learns anything. A creature shipped without a faint
animation stays standing when it should fall, and the first person to notice is
a player.

## Consequences

**The difference the build enforces is between a decision and an omission.** Both
produce the same behaviour at runtime; only one of them was chosen by somebody,
and the manifest is where that choice is recorded and reviewed.

A fallback is visible in a diff, which means "still using idle for hurt" is a
question a reviewer can ask six months later. An automatic fallback leaves no
trace to ask about.

The vocabulary itself must stay closed and checked, or a fallback could name a
clip that does not exist either. Spec 16 makes that a meta-test rather than two
lists somebody compares by eye.
