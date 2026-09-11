# 0070 — A map is found by its filename, and the validator makes that true

**Status:** Accepted
**Date:** 2026-09-11
**Recorded in:** spec 14, section 7

## Context

`WorldSandbox` builds a table of every map in `game/maps/` before it can do
anything, because a save holds a map id (decision 0040) and a warp names one. It
built that table by **loading and instantiating every scene in the folder** and
asking each root for its `map_id`.

The comment on it argued the case plainly: the filename is not the id, the two
agree for everything the tools produce, nothing enforces it, and a map answering
to the wrong name would be a save pointing at the wrong place.

The argument was right. The remedy was in the wrong place.

## How it was found

The test suite had become slow enough to complain about. Measured rather than
guessed at: of 284 seconds across 768 tests, **272 were one suite of 36** —
`world_sandbox_test`, which builds a world per test. Every other test in the
project together came to twelve seconds.

Timing the discovery, file by file:

| map | parse | instantiate |
| --- | --- | --- |
| `starter_cave.tscn` | 9 ms | 0 ms |
| `starter_field.tscn` | 5 ms | 0 ms |
| `test2.tscn` | 2 ms | 0 ms |
| `test1.tscn` | **6 172 ms** | 0 ms |

The cost is the text parse, and it is repaid every time: Godot's resource cache
holds scenes weakly, so a discovery that drops its reference and frees its
instance leaves nothing behind, and the next world parses all of it again.

`test1.tscn` was 66 MB because a `VltFoliagePatch` serialised its generated mesh
into the scene — a separate defect, fixed alongside this one. But the two are
worth separating: **the foliage bug made this visible, and this one would have
been paid by any real map.** Startup cost here scales with the *size* of every
map in the folder, not with how many there are.

## Decision

**The filename is the id**, and `VltMapValidator` enforces it. Discovery lists
the directory and opens nothing.

The check is skipped for a map with no `scene_file_path` — a fixture built in
code is a real map to every other check in the validator, and this rule is about
files.

## Options rejected

**A generated index**, id to path, written by the content build and checked fresh
by CI, the way `content/generated/` already works. It keeps filenames free, which
is the only thing the chosen option gives up. Rejected because it is a second
artefact to regenerate and a second thing that can be stale, bought for a freedom
nobody has asked for: every map the tools produce is already named after its id.

**Leaving it alone** once the foliage bug was fixed. Maps would go back to being
small and the parse would stop mattering. Rejected because it puts a cost
proportional to the size of the world on every startup, waiting for the first map
big enough to bring it back — and the thing that would bring it back is success.

## Consequences

`world_sandbox_test` went from 272 seconds to 35, with the 66 MB map still in the
folder. What is left is `VltRestPoint.nearest()`, which walks into neighbouring
maps to find somewhere to recover — that one genuinely needs what is inside a
map, and it falls away as maps return to a sane size.

**Renaming a map file is now a rename of the map.** It always should have been;
the difference is that forgetting the other half is now caught by a button rather
than by a save that loads into nothing months later.
