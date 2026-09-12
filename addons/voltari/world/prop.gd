class_name VltProp
extends Node3D

## A model standing on a map, where it stands and at the size it is.
##
## **A cell could not say this.** A `GridMap` cell carries an item, one of
## twenty-four turns and no scale of its own, so a fence could be painted along
## four directions and at one size. Anything an author wants at an angle, or
## bigger, or made of several models standing together, has to be a node — and
## once it is a node it needs an answer to the question a painted cell already
## had: does it stop you, and where.
##
## ## It stops you where its mesh is
##
## The same answer decision 0072 gave for painted models: the polygon the
## geometry occupies below the walker's reach, derived when the map is read and
## never stored. Nothing here is authored twice and nothing can go stale, because
## there is no copy of it — turning a prop turns its footprint because the
## footprint *is* the turned mesh, measured.
##
## ## Why this is a type and not a flag on any node
##
## A map already holds models that are not props: the three `MeshInstance3D`
## nodes in `test1` were placed before any of this existed and have never stopped
## anybody. Making every mesh on a map block would change what those maps mean,
## silently and everywhere at once — the exact failure decision 0072 refused when
## it made the palette, rather than a migration, decide how a blocking layer is
## read.
##
## Being a prop is therefore something a node *is*, declared by placing one. An
## ordinary model beside it stays what it always was: art.

## Whether this prop stops anybody.
##
## True by default, because a thing standing in the world stopping you is the
## expectation and the opposite is the exception — a flower, a rug, a painted
## sign on the ground. An author who wants one of those says so once, here, and
## the map says what it means.
@export var blocks: bool = true


## Every prop under a node, itself included, without descending into one.
##
## Walked rather than listed on the map, because a prop is an ordinary node an
## author can group, rename or reparent, and a list would be a second place to
## keep correct. The map's own accessor is `VltWorldMap.props`.
##
## **A prop is a leaf here even when it holds another one.** Its shape is built
## from every mesh below it, so descending would measure a nested prop's geometry
## twice and hand the walker two copies of the same wall. The outer prop owns
## everything under it, which also means an inner prop's `blocks` says nothing —
## a trap worth knowing about, and one the map validator reports.
static func props_under(root: Node) -> Array[VltProp]:
	var found: Array[VltProp] = []
	if root == null:
		return found

	var here: VltProp = root as VltProp
	if here != null:
		found.append(here)
		return found

	for child: Node in root.get_children():
		found.append_array(props_under(child))
	return found


## Every prop nested inside another, which is a mistake rather than a shape.
##
## Kept beside the rule it is the exception to, so the two are read together.
static func nested_under(root: Node) -> Array[VltProp]:
	var found: Array[VltProp] = []
	for prop: VltProp in props_under(root):
		for child: Node in prop.get_children():
			found.append_array(_every_prop_under(child))
	return found


static func _every_prop_under(node: Node) -> Array[VltProp]:
	var found: Array[VltProp] = []
	var here: VltProp = node as VltProp
	if here != null:
		found.append(here)
	for child: Node in node.get_children():
		found.append_array(_every_prop_under(child))
	return found
