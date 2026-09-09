class_name PresentationEntry
extends RefCounted

## One species' presentation manifest, typed (spec 16, section 5).
##
## Here rather than in `addons/voltari/loaders/` with the other six, and the
## reason is decision 0046: the engine has no presentation layer, deliberately.
## A type describing a scene, an art-directed clip vocabulary and a display
## height is this game's, not the reusable engine's.
##
## Plain data. What plays a clip is the runtime's business.

var id: String = ""

## The `.tscn` to instance.
var scene_path: String = ""

## Intended display height in metres.
var height: float = 1.0

## Slot to its takes, in the order the manifest gave them.
var takes: Dictionary[String, PackedStringArray] = {}

## Slot to the slot it borrows from. A written decision, never an inference
## (decision 0047) — which is why it is kept apart from `takes` rather than
## resolved away on load: a reviewer can still see that `hurt` is borrowing.
var fallbacks: Dictionary[String, String] = {}

## Clips the model carries that no slot claims. Playable by name, asked for by
## nothing.
var extras: PackedStringArray = PackedStringArray()

## Clips that hide a part rather than animate one.
var stow: PackedStringArray = PackedStringArray()


## The takes to play for a slot, following a declared fallback once.
##
## Once, not repeatedly: the build refuses a fallback whose target has no takes,
## so a chain cannot exist — and following one here anyway would make the engine
## tolerant of content the build already rejected.
func takes_for(slot: String) -> PackedStringArray:
	if takes.has(slot):
		return takes[slot]
	if fallbacks.has(slot) and takes.has(fallbacks[slot]):
		return takes[fallbacks[slot]]
	return PackedStringArray()


func has(slot: String) -> bool:
	return not takes_for(slot).is_empty()


## Every clip name the manifest mentions, however it mentions it. What makes
## "nothing is dropped" countable rather than aspirational.
func every_clip() -> PackedStringArray:
	var all: PackedStringArray = PackedStringArray()
	for slot: String in takes:
		all.append_array(takes[slot])
	all.append_array(extras)
	all.append_array(stow)
	return all
