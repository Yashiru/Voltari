class_name VltSettings
extends RefCounted

## What the player configured, in its own file (spec 18, section 4;
## decision 0052).
##
## Not a save section, and the difference is meaning rather than mechanism. They
## **outlive a save** — deleting a playthrough must not reconfigure somebody's
## controls. They are **shared by every save**. And they are **read before a save
## is chosen**, because language decides what the menu that picks one is written
## in.
##
## Written exactly the way a save is, through the same class: temporary file,
## then replace (spec 13, section 7). Two files, one discipline, no second
## mechanism.
##
## **A file that will not parse starts the game on defaults.** The asymmetry with
## a save is deliberate: a save that cannot be read is the player's history and
## is worth interrupting them for, and a volume slider is not.

const FILE: String = "user://settings.json"

## Raised when a field's meaning changes, never when one is added — an absent
## field takes its default, which is the same tolerance spec 13 section 3
## describes and for the same reason.
const VERSION: int = 1

const VERSION_KEY: String = "version"
const LANGUAGE_KEY: String = "language"
const TEXT_SPEED_KEY: String = "text_speed"
const VOLUME_KEY: String = "master_volume"

## Empty means the system's own. A stored locale is a deliberate choice; the
## absence of one is not a choice at all, and the two must not be confused.
var language: String = ""

## A multiplier on how long a line is held (spec 17, section 2). One is the
## pace the stage was tuned at.
var text_speed: float = 1.0

var master_volume: float = 1.0


static func defaults() -> VltSettings:
	return VltSettings.new()


## Reads, or hands back defaults. Never fails: there is no state of the world in
## which the right answer is refusing to start.
static func load_from(path: String = FILE) -> VltSettings:
	return from_dictionary(VltSaveStore.read(path))


func save_to(path: String = FILE) -> bool:
	return VltSaveStore.write(path, to_dictionary())


func to_dictionary() -> Dictionary:
	return {
		VERSION_KEY: VERSION,
		LANGUAGE_KEY: language,
		TEXT_SPEED_KEY: text_speed,
		VOLUME_KEY: master_volume,
	}


## Read through the save layer's own tolerant helpers rather than a second set:
## a hand-edited settings file faces exactly what a hand-edited save does.
static func from_dictionary(stored: Dictionary) -> VltSettings:
	var settings: VltSettings = VltSettings.new()
	settings.language = VltSaveSection.read_string(stored, LANGUAGE_KEY)
	settings.text_speed = _ratio(stored, TEXT_SPEED_KEY, settings.text_speed)
	settings.master_volume = _ratio(stored, VOLUME_KEY, settings.master_volume)
	return settings


## A multiplier that is zero, negative or absurd is not a setting somebody
## chose; it is a file that was edited. Clamped rather than trusted, because the
## alternative is a game with no sound and no way to work out why.
static func _ratio(stored: Dictionary, key: String, fallback: float) -> float:
	var value: Variant = stored.get(key, fallback)
	var number: float = fallback
	if value is float:
		number = value as float
	elif value is int:
		number = float(value as int)
	return clampf(number, 0.0, 4.0)
