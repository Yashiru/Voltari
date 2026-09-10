class_name Translations
extends RefCounted

## Registers the translation tables (spec 17, section 5).
##
## In code rather than in the project settings, and for a reason that outlives
## the convenience: **the same list serves the game and the tests**. A project
## setting is loaded by a running game and not by anything else, so the check
## that every key exists would be checking a file nothing had read.
##
## Adding a language is a line here. Adding a table is a line here. Both are
## visible in a diff, which a project setting is not.

const TABLES: Array[String] = [
	"res://game/localisation/battle.en.translation",
	"res://game/localisation/world.en.translation",
]


## Idempotent, because everything that needs translations calls it and none of
## them knows whether it is first.
static func install() -> void:
	for path: String in TABLES:
		if not ResourceLoader.exists(path):
			push_warning("no translation table at %s" % path)
			continue

		var table: Translation = load(path) as Translation
		if table == null:
			continue
		if _installed.has(path):
			continue

		TranslationServer.add_translation(table)
		_installed[path] = true


## What has already been added. Kept here rather than asked of the server,
## which offers no way to enumerate what it holds — and adding the same table
## twice is the sort of harmless that makes a later measurement confusing.
static var _installed: Dictionary[String, bool] = {}
