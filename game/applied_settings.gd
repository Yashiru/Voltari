class_name AppliedSettings
extends RefCounted

## Turns what the player configured into what the engine does (spec 18,
## section 4).
##
## The split is deliberate: `VltSettings` is the values and the file, and knows
## nothing about Godot's locale or its audio buses. This is the half that does,
## and it lives in `game/` because applying a volume is not the reusable
## engine's business.
##
## Without it the settings were written, tested and read by nobody — a file the
## player could edit and a game that never looked.

## Loads, applies, and hands back what it applied. Returning them matters: text
## speed is not something a server holds, so whoever paces a screen has to be
## told.
static func install() -> VltSettings:
	var settings: VltSettings = VltSettings.load_from()

	# An empty locale is not a choice, so it is not applied. Godot's own default
	# is the system's, which is what "no choice" means.
	if not settings.language.is_empty():
		TranslationServer.set_locale(settings.language)

	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Master"), linear_to_db(settings.master_volume)
	)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), settings.master_volume <= 0.0)

	return settings
