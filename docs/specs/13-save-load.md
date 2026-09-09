# 13 — Save, load and migration

**Status:** Draft
**Depends on:** specs 03, 09; decisions 0001, 0025

A save file outlives every version of the game that reads it. A format decided
carelessly is paid for at every release afterwards, which is why this comes
before the systems that will fill it.

---

## 1. Where it lives

**L5 does the file work**: writing bytes, replacing a file, reading one back.
Nothing else touches a path.

The *data* is assembled by whoever owns it. The core already serialises to plain
dictionaries and back (spec 03, invariant 9); the save reuses that shape rather
than inventing a second one. Nothing below L5 learns that files exist.

## 2. Each system declares its part

A system that wants to persist something says so: a **key**, a **version**, and
the pair of functions that write and read it.

Nothing enters a save by accident. What a save contains is readable in one place
rather than inferred from whatever happened to be reachable from a root object.
And a new system changes nothing about existing saves until it declares
something.

The alternative — snapshotting the whole world — was rejected because the save
would then take the shape of every system's internals, and a refactor nobody
thought of as risky would break every existing file.

**The hazard this carries is silent loss.** A system that forgets to declare its
part runs perfectly and loses the player's data. Two things answer it: a save
round-trip test is part of declaring a section, not an optional extra, and the
meta-test of section 8 fails when a declared section has no such test.

## 3. A tolerant reader, and what tolerance does not cover

There is **one reader per section**, not a chain of version-to-version
migrations. It accepts fields that are absent and supplies defaults.

That covers the common change by far: a version adds a field, and older saves
simply do not have it.

**It does not cover a field whose meaning changed**, or one that was renamed. A
default cannot help there: the value is present, it reads without error, and it
plays wrong. That is what the **section version** is for — the reader branches on
it, and a change of meaning is a change of version. Tolerance is about absence,
never about meaning.

The rule that follows, and it is the one that keeps this design honest: **never
reuse a field name for a different meaning.** Add a new one and leave the old
where it is. A tolerant reader makes that cheap; ignoring it makes tolerance a
trap.

## 4. What cannot be read is kept, not dropped

A section the game does not recognise — from a newer version, or from a system
this build does not have — is **carried through verbatim** and written back
untouched.

This is what stops "load what you can" from meaning "lose the rest". Without it,
a partly-understood save is rewritten complete on the next write, and everything
unread is gone for good — the player finding out weeks later, by looking for
something that is missing.

Keeping the raw section costs a dictionary. Losing it costs a save.

## 5. An incomplete read is announced, and confirmed

When any section could not be read, the game **says so, names what it could not
read, and asks before continuing**. It does not load silently, and it does not
refuse outright.

Refusing outright was the stricter option and it is what spec 09 does for
content — but content is the developer's problem and a save is the player's.
Refusing leaves them unable to play, which is the worst possible moment to be
right.

Loading silently was the other, and it is worse: the player learns nothing and
proceeds on a save they cannot trust.

**Before writing over a save that read incompletely, the previous file is kept.**
The confirmation buys informed consent; the backup is what makes the consent
recoverable if it was given too quickly.

## 6. No saving mid-battle

A save never contains battle state, and never contains generator state.

The battle model is the most-changed part of the engine, and putting it in a file
that must be read for years would make every change to it a migration. Keeping it
out costs one thing, stated plainly: **an application killed mid-battle loses
that battle.** On mobile that will happen. It is accepted.

## 7. Writing must survive being interrupted

A save is written to a temporary file, flushed, and only then moved over the
real one. A crash — or a battery dying — during a write must leave the previous
save intact.

The failure this prevents is the worst one a save system has: not losing the new
data, but destroying the old while writing it.

## 8. Testing obligations

- **Every declared section round-trips.** Written, read back, identical. This is
  part of declaring a section, and a meta-test fails when a section has no such
  test — which is what makes the silent-loss hazard of section 2 answerable.
- **An older save loads.** For each version the format has had, a fixture that
  reads and produces the values it should. Fixtures are committed; they are the
  only evidence that yesterday's saves still work.
- **An unknown section survives a round trip**, byte for byte.
- **A truncated or corrupted file is reported, not crashed on**, and the previous
  save is still there afterwards.
- **A newer version reads as incomplete** rather than as damaged, because the two
  say different things to the player.

## Open points

- **What the sections actually are.** Party, inventory, position, flags: each
  belongs to a system that has no spec yet. This defines how a section is
  declared, not which ones exist.
- **Multiple save slots**, and whether the game has one file or several. It
  changes nothing here — the mechanism is per-file — but it is undecided.
- **Tampering.** A JSON save is trivially editable. Whether that matters is a
  design question about what kind of game this is, not a technical one, and
  nothing here tries to prevent it.
