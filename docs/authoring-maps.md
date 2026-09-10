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

Models are **third-party until they are not**, and third-party assets never enter
this repository (decision 0027). Put them in the quarantine:

```
game/assets/placeholders/<pack-name>/
```

That path is git-ignored and guarded on the index, the tree, the whole history
and every export preset. Never stage anything under it, and prefer path-scoped
`git add` over `-A` at the repository root.

Godot 4.7 imports `.fbx` natively — there is nothing to install. Drop the files
in and let the editor import them.

## 2. Build the palette

In the **Maps** dock: set *Models folder* and *Tile library*, then **Build tile
library**.

It reads every model in the folder and writes a `MeshLibrary` — the palette a
`GridMap` paints from. Both paths default inside the quarantine, because a
library built from third-party models is derived from them.

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

## 5. Place what the map carries

Add these as children of the map root — or under a grouping node, which the
plugin follows:

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
