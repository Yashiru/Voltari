class_name ClipMap
extends RefCounted

## The quarantine-era bridge from a model's clip names to our vocabulary
## (spec 16, section 4).
##
## For a fakemon this does nothing: the manifest already names our slots. It
## exists because the quarantined library carries its own naming — a two-letter
## context and a two-digit slot — and 856 models is too many to map by hand.
##
## **Nothing is dropped.** Every name that goes in comes out somewhere: a slot's
## takes, an effect track, a stow clip, or an extra. There is no fourth outcome
## and no silent discard, which is precisely how the first mapping attempt
## failed unnoticed.

# --- our vocabulary ----------------------------------------------------------

const BATTLE: Array[String] = [
	"enter", "idle", "attack_physical", "attack_special", "hurt", "faint"
]
const FIELD: Array[String] = ["field_idle", "walk", "run"]
const COMPANION: Array[String] = ["companion_idle", "happy", "unhappy", "eat"]

## Slots whose clip holds rather than loops. Everything not here loops.
const LOOPING: Array[String] = ["idle", "field_idle", "companion_idle", "walk", "run"]

# --- the source's own standard ----------------------------------------------

## The code is what disambiguates one context from another: `wait` is the battle
## idle under `ba10`, the field idle under `fi01`, and the companion idle under
## `kw01`. Nothing but the code separates them.
const BY_CODE: Dictionary[String, String] = {
	"ba01": "enter",
	"ba10": "idle",
	"ba20": "attack_physical",
	"ba21": "attack_special",
	"ba30": "hurt",
	"ba41": "faint",
	"fi01": "field_idle",
	"fi20": "walk",
	"fi21": "run",
	"kw01": "companion_idle",
	"kw30": "unhappy",
	"kw32": "happy",
	"kw50": "eat",
}

## What each code's clips are actually called, so a known code carrying an
## unknown word is recognised as the one-off it is rather than absorbed.
const WORD_OF_CODE: Dictionary[String, String] = {
	"ba01": "land",
	"ba10": "wait",
	"ba20": "buturi",
	"ba21": "tokusyu",
	"ba30": "damage",
	"ba41": "down",
	"fi01": "wait",
	"fi20": "walk",
	"fi21": "run",
	"kw01": "wait",
	"kw30": "hate",
	"kw32": "happy",
	"kw50": "eat",
}

## Names from the older extraction, which carries no code at all — about a
## fifth of the library. They are all battle clips, so a bare `wait` is the
## battle idle. That is an assumption, and it is the only one here.
const BARE: Dictionary[String, String] = {
	"land": "enter",
	"wait": "idle",
	"buturi": "attack_physical",
	"tokusyu": "attack_special",
	"damage": "hurt",
	"down": "faint",
}

## Suffixes the conversion leaves behind. Stripped before anything is matched,
## or one take reads as two variants.
const NOISE: Array[String] = [
	"_FBX_OVERRIDE", "_HAT_OVERRIDE", "_euler", "_Euler_EveryframeCompressed",
	"_RemovedScale", "_mtAdjust", "_mtCleanup",
]

## Played alongside its slot, never instead of it.
const EFFECT_SUFFIX: String = "_FX"


## What a model's clips turned into.
class Mapping:
	extends RefCounted

	## Slot to its takes, in the order the model listed them.
	var takes: Dictionary[String, PackedStringArray] = {}

	## Slot to the effect tracks that accompany it.
	var effects: Dictionary[String, PackedStringArray] = {}

	## Clips that hide a part rather than animate one.
	var stow: PackedStringArray = PackedStringArray()

	## Everything else, kept by name. A species' own flourish lives here.
	var extras: PackedStringArray = PackedStringArray()

	func slots() -> Array[String]:
		var found: Array[String] = []
		for slot: String in takes.keys():
			found.append(slot)
		found.sort()
		return found

	## Every clip that went in, so a caller can prove nothing was lost.
	func accounted() -> int:
		var n: int = stow.size() + extras.size()
		for slot: String in takes:
			n += takes[slot].size()
		for slot: String in effects:
			n += effects[slot].size()
		return n


static func all_slots() -> Array[String]:
	var every: Array[String] = []
	every.append_array(BATTLE)
	every.append_array(FIELD)
	every.append_array(COMPANION)
	return every


static func loops(slot: String) -> bool:
	return LOOPING.has(slot)


## Maps a model's clip list. The order of the rules is the whole design:
## noise off, stow out, effects aside, then code, then bare word, then extra.
static func of(clip_names: PackedStringArray) -> Mapping:
	var mapping: Mapping = Mapping.new()

	for original: String in clip_names:
		if _is_stow(original):
			mapping.stow.append(original)
			continue

		var cleaned: String = _without_noise(original)
		var is_effect: bool = cleaned.ends_with(EFFECT_SUFFIX)
		if is_effect:
			cleaned = cleaned.substr(0, cleaned.length() - EFFECT_SUFFIX.length())

		var slot: String = _slot_of(cleaned)
		if slot.is_empty():
			mapping.extras.append(original)
			continue

		var into: Dictionary[String, PackedStringArray] = (
			mapping.effects if is_effect else mapping.takes
		)
		if not into.has(slot):
			into[slot] = PackedStringArray()
		into[slot].append(original)

	return mapping


## A stow clip drives the stowable-parts feature, not the animation player. Both
## spellings occur — `HideLeftEar` and `hide_left_ear`.
static func _is_stow(name: String) -> bool:
	return name.to_lower().begins_with("hide")


## Repeatedly, because a name can carry two — `..._FBX_OVERRIDE` after a `_1`.
static func _without_noise(name: String) -> String:
	var cleaned: String = name
	var changed: bool = true

	while changed:
		changed = false
		for suffix: String in NOISE:
			if cleaned.ends_with(suffix):
				cleaned = cleaned.substr(0, cleaned.length() - suffix.length())
				changed = true
		# A trailing `_<digits>` is glTF de-duplicating a repeated name.
		var underscore: int = cleaned.rfind("_")
		if underscore > 0 and cleaned.substr(underscore + 1).is_valid_int():
			cleaned = cleaned.substr(0, underscore)
			changed = true

	return cleaned


## Empty when nothing recognises it.
static func _slot_of(cleaned: String) -> String:
	var underscore: int = cleaned.find("_")

	if underscore == 4 and BY_CODE.has(cleaned.substr(0, 4)):
		var code: String = cleaned.substr(0, 4)
		# The code says which context; the word still has to be that context's
		# own, or a species one-off in a known context would be absorbed into a
		# slot it does not belong to.
		if _word_of(cleaned.substr(5)) == WORD_OF_CODE[code]:
			return BY_CODE[code]
		return ""

	return BARE.get(_word_of(cleaned), "")


## `waitA01` and `wait01` and `damageS01` all reduce to their word.
static func _word_of(part: String) -> String:
	var word: String = ""
	for index: int in range(part.length()):
		var glyph: String = part[index]
		if glyph.to_lower() != glyph or glyph.is_valid_int():
			break
		word += glyph
	return word
