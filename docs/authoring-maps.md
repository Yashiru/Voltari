# Authoring a map

How to build one, with what. The *why* is spec 14 and decisions 0038, 0039, 0054
and 0027; this is the part you follow.

The editor is Godot's. The plugin adds the four things Godot cannot know about a
Voltari map: how to start one, what its nodes are, where they sit, and whether it
is sound.

---

## Before anything: enable the plugin

**Project → Project Settings → Plugins → Voltari Maps.**

It is not enabled in `project.godot` for you, because that file carries local
editor state and this repository does not commit changes to it on your behalf.

## 1. Get models in

Tile packs are **third-party until they are not**, and a third-party asset never
enters this repository (decision 0027). A licence to use one in a game is not a
licence to redistribute it, and a repository redistributes. Put them here:

```
game/assets/species/brawl_arena/
```

That path and the `.meshlib` built from it are git-ignored and guarded on the
index, the tree, the whole history and every export preset. Never stage anything
under them, and prefer path-scoped `git add` over `-A` at the repository root.

The creature models beside them are the project's own and *are* committed, through
LFS (decision 0071). A pack you made yourself belongs there too, outside the two
guarded paths, and `.gitattributes` will send its binaries to LFS on its own.

Godot 4.7 imports `.fbx` natively — there is nothing to install. Drop the files
in and let the editor import them.

## 2. Build the palette

In the **Maps** dock: set *Models folder* and *Tile library*, then **Build tile
library**.

It reads every model under the folder and writes a `MeshLibrary` — the palette a
`GridMap` paints from. Both paths default inside the quarantine, because a
library built from third-party models is derived from them.

### Folders are categories

A subfolder becomes part of the item's name: `<root>/Plants/Bush_1.fbx` is the
item `Plants/Bush_1`. The `GridMap` palette sorts and filters by name, so the
plants arrive together and typing `plants` in the palette's search box narrows to
them. Nest as deep as you like — `Ground/Paths/Slab` is a category inside a
category.

Nothing else has to know. The grass, grain, contact and roughcast fields match on
the name, so `Plants/` in one of them is every plant at once — the trailing slash
is what keeps it from also matching a crate called `Plantation`.

A model at the root of the folder keeps its bare name and no category, which is
why an existing flat palette can gain folders without any of its items moving.

**Sort a pack on the way in.** Moving a model between folders renames it, with
the consequence below: a palette built flat and tidied afterwards grows one
orphan per file you moved.

### Every tile stands on its own origin

A model does not arrive at the origin. A finished pack is authored as scenes, so
each piece carries the spot it stood on in the one it was cut from — a house in
the Town Islands pack sits 37 m east and 28 m north of its own origin. A cell
places an item's *origin*, so painted as-is the model would appear a block away
from the cell you clicked.

The build moves the geometry so the middle of its base is on the origin. Every
build, so rebuilding straightens a palette made before this existed — and moves
every cell already painted with one.

**In the geometry, not in the item.** A `MeshLibrary` can carry a transform per
item, and that only moves what the `GridMap` draws. Everything else that measures
the mesh — the grass working out what footprint to part around, the foliage
looking for the top of a tile — would go on reading the artist's coordinates and
be wrong by the whole offset. The mesh is where the mesh is, and then there is
nothing to remember.

The cost is the importer's whole-mesh shortcut, which keeps LODs and shadow
meshes for a model taken in one piece. It still applies to a model that already
stands on its origin; none of the 303 here does, because the offset they carry is
a node transform and a transformed part was already being rebuilt.

**Turn off `Cell > Center Y` on each layer.** A `GridMap` centres on all three
axes by default, so a cell's origin is half a cell *above* the grid plane. Now
that a tile's base is its origin, that half cell is the height everything floats
at — 50 cm at a cell size of 1. Centring on X and Z is what you want and should
stay on.

Run it as often as you like. **Item ids never move**: an existing library is
added to rather than replaced, an item keeps its id for as long as its name does,
and an item whose model has gone keeps its id rather than freeing it for
somebody else. That is what stops a rebuild from silently repainting every map
you already made.

Renaming a model file makes a new item and leaves the old one behind. Delete the
stale item by hand if it bothers you — but understand that its id then falls out
of use permanently, which is the intended outcome.

### Switching a layer to a different library repaints it

Ids are stable *within* one library, and they mean nothing across two. A
`GridMap` stores an id per cell, so pointing an already-painted layer at another
library keeps every cell exactly where it is and changes what each one **is** —
item 0 of the old palette becomes item 0 of the new one, everywhere at once.

There is no warning and nothing to undo afterwards. Either start from an empty
layer, or clear it before you change `mesh_library`.

The starter maps are painted from `game/maps/tiles.meshlib` — the three grey
boxes — so this applies to them the moment you reach for a real palette.

### What a clone sees

The library is quarantined and the maps are committed, so a fresh clone opens a
map whose palette is missing. **The map still works**: a `GridMap` keeps its
cells with no mesh library at all, so the world stays exactly as walkable as you
painted it and turns invisible. Nothing to work around.

## 3. Make the map

In the **Maps** dock: a *New map id*, a width and a height, optionally the name
of the tile to floor it with, then **New map**. It writes
`game/maps/<id>.tscn` and opens it.

The id is an identifier, not a title: lower case, digits and underscores,
starting with a letter. A save holds it (decision 0040), so renaming a map later
is a migration rather than a rename.

**The file must be named after the id** — `starter_field.tscn` holds
`starter_field`. The game lists this folder and takes each filename as an id
without opening anything, so a map whose file says otherwise is one it can never
find, and a save holding that id loads into nothing. **Validate maps** reports it.
Rename the file and the `map_id` together, or neither.

**It refuses to overwrite.** Everything else it refuses is a typo caught early;
writing over a painted map destroys work that has no other copy.

What you get is a rectangle of ground, all three layers wired and sharing the
palette, and nothing else. A brand-new map has no rest point, so the validator
will tell you it cannot recover a defeat — that is true, and it is the first
thing to fix rather than something to hide.

## 4. Paint the three layers

A map scene is a `VltWorldMap` with three `GridMap` children. Select one and use
Godot's own GridMap editor.

| Layer | What it says | Read by |
|-------|--------------|---------|
| `terrain` | this cell exists | walkability |
| `blocking` | this cell stops you | walkability |
| `decor` | nothing | nobody (decision 0054) |

A cell with no terrain is off the map, and off the map blocks the way a wall
does — so no map needs a fence painted around its edge.

Nothing detects a wall you can walk through. Painting a wall mesh into `decor`,
or terrain with no `blocking` under a rock, produces exactly that, and no test
will ever fail because of it. It is a visual mistake and you are the only check.

### A model in `blocking` blocks what it covers

A cell is one question and a house is five cells wide. Paint one into `blocking`
and the plugin fills in the rest of its footprint a moment later, with `_blocked`
— an invisible item the tile library keeps in every palette. Erase the house and
those cells come back, except any a second model still covers.

**The footprint is what the model occupies below two metres**, which is roughly
the character: the question is what they would walk into. A canopy, an eave, an
arch or a balcony is something you walk under and takes no cells. It is measured
from the geometry in that band and not from the bounding box, which for a palm
would block the whole clearing it shades.

A cell counts as covered once the model takes more than a twentieth of it, so a
wall overhanging its neighbour by a millimetre does not take that neighbour, and a
corridor drawn exactly two cells wide still admits somebody.

**They are ordinary painted cells, so correct them freely.** Erase one to leave a
doorway through a house the model does not have; paint `_blocked` by hand
anywhere you want something stopped that no model stands on. Nothing is derived
at runtime — the map stays the authority on itself, and the validator goes on
reading it. What you changed sticks until you touch that model again.

Two things worth knowing. Only an *empty* cell is ever filled in: a cell already
holding something is one you put there, and losing your tile is worse than
noticing a gap. And this does not go through undo — undoing a paint removes the
model and its blockers go with it, but undoing past that will not bring them
back. They are cells like any other; paint over them.

A palette built before `_blocked` existed simply does nothing here. Rebuild the
tile library and the cells start filling in.

## 5. Place what the map carries

Add these as **direct children of the map root**. Not under a grouping node: the
map reads its own children and looks no deeper, so a warp tidied into a `Warps`
folder is a warp the game cannot see. The gizmo still draws it, which makes this
worth knowing before you tidy.

| Node | What it does |
|------|--------------|
| `VltWarp` | leads to a map, a cell and a facing |
| `VltEncounterZone` | a rectangle naming an encounter table |
| `VltEvent` | fires at a cell, on a named trigger |
| `VltRestPoint` | where a defeat sends you |

Each draws an outline on the cells it claims, with a post so it reads edge-on and
an arrow for the facing you arrive on. **Drag them and they snap.** The cell is
what the game reads and it stays the truth: a drag is converted and snapped back,
so nothing is ever left between two cells. Typing a cell in the inspector moves
the node instead.

Everything else about them — where a warp leads, which table a zone names, what
an event does — is `@export`s in the inspector. Events are typed nodes, and their
steps are child nodes (spec 15).

### Props you want to scale are not grid cells

**A `GridMap` cell carries an item id and one of 24 orthogonal orientations, and
no scale at all.** Choosing a size while painting does not exist, and that is the
shape of the tool rather than a missing feature.

So anything whose size or angle you want to choose goes in as an ordinary node:
drag the model from the FileSystem into the scene as a child of the map, and set
position, rotation and scale in the inspector like any 3D object. Nothing reads
it — the same as the decoration layer, for the same reason (decision 0054).

**Snap to cells** in the 3D toolbar moves the selected props onto the nearest
cell. Height, rotation and scale are left alone: a prop sunk into the floor or
raised onto a ledge is art. It is on demand rather than continuous, because a
prop half a cell into a doorway is a legitimate thing to want.

`cell_scale` on a `GridMap` scales everything in that layer at once, which is the
answer to "all my tiles are twenty percent too big" and to nothing else.

### The grid is one metre, and the art is drawn at half

`cell_size` is how far apart cells are; `cell_scale` is how big the mesh in one is
drawn. **They answer two questions and both have to be set.** The tile library is
authored at two metres a tile, so on a one-metre grid it is drawn at half — and a
tile then fills its cell exactly instead of overlapping its neighbours four times
over.

New maps get both from `VltNewMap.CELL_SIZE` and `ART_SCALE`, and so do the
starter maps. **A map you painted before carries its own**: select each of its
three `GridMap` layers and set `Cell > Size` to 1 and `Cell > Scale` to 0.5.
Nothing is lost either way — cells keep their coordinates, so the map changes
size and not shape, and setting the two back undoes it.

One metre is a cell a person fits in. At two, the 1.7 m character stood on a tile
nearly wider than they are tall and everything read as furniture built for
somebody else. Walking speed is unaffected: how long a cell takes is derived from
its width, so the player crosses twice as many cells a second at the same
metres a second.

### Cells are centred vertically

`cell_center_y` is on by default, so the centre of a ground cell is **half a cell
up**, not at zero. Two consequences, both already handled, both worth knowing
before you wonder why something floats: gizmo outlines clear the tile they sit on,
and the player capsule stands on the floor instead of being buried to the chest.

If you place a prop by typing numbers rather than dragging, this is the offset
you are missing.

## 6. Check it

**Validate maps** in the dock, whenever you like and certainly before committing.

It runs over **every** map in the folder rather than the one you are editing,
because what it catches is what no single map can see: a warp's destination lives
in a different file from the warp.

It reports all problems at once — a map pass fixes ten broken warps in one go or
ten times over. What it will tell you about:

- a warp naming a map or a cell that does not exist, or sitting where nobody can
  stand
- a zone naming an unknown encounter table, covering nothing, or overlapping
  another
- two maps claiming one id, which a save cannot tell apart
- a map no warp leads to
- an event line that no translation table has, and a flag read by nothing that
  sets it
- **no rest point anywhere**, or a map that can reach none — content a defeat
  cannot recover from

An empty folder is reported as a problem, not as a pass. A typo in the path would
otherwise read as success.

## 7. Walk it

`F5` in the editor runs the sandbox. It **finds** the maps in `game/maps` rather
than being told about them, so the one you just painted is there without editing
any code.

Press **M** for the list, pick a map, and you are on it. You arrive on its rest
point if it has one — that is already "where you come round on this map", so
there is no second concept for "where you start". Otherwise the first cell you
can stand on.

The list only appears when there is more than one map to choose between.

## 8. Commit

Path-scoped, always:

```bash
git add game/maps/your_map.tscn
```

The suite validates the committed maps too, so a broken door fails CI as well as
the dock.

---

## The starter maps

`tools/maps/build_starter_maps.gd` generates `starter_field` and `starter_cave`
in code. They exist so there is something to walk on before anybody paints, and
they are ordinary scenes — open one and paint over it.

**Re-running that script overwrites whatever you painted.** It is a starting
point, not a build step.
