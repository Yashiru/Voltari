class_name BattleLogReader
extends RefCounted

## Turns a filtered log into something a player watches (spec 17, section 2).
##
## A queue drained with `await`: take an event, play what it looks like, wait for
## that to finish, take the next. `await` is banned in the core and correct here
## — decision 0050 says why in a table, and the short form is that a reader
## persists nothing, is never saved, and exists precisely because time passes.
##
## **It reads the log and nothing else** (decision 0049). It is handed a view and
## advances it; it never sees a battle state, and a lint over this directory
## enforces that rather than trusting it.
##
## **Skipping is not a second path.** The reader has no skip flag and no branch:
## it always awaits, and a stage that is skipping simply returns instantly. That
## is what makes "watched and skipped end the same" a property rather than a
## promise to keep two code paths in step.

## Event kinds that legitimately show nothing. Anything else the reader does not
## recognise is a mechanic somebody added without telling the UI, and it says so.
const SILENT_KINDS: Array[String] = [
	VltLogPendingInput.KIND,
	VltLogCaptureShake.KIND,
	VltLogEffectiveness.KIND,
	VltLogDamage.KIND,
	VltLogTurnStart.KIND,
]


var view: VltBattleView
var stage: BattleStage

var _registry: VltEffectRegistry
var _moves: Dictionary[String, VltMoveDefinition] = {}
var _species: Dictionary[String, VltSpecies] = {}
var _party: Array[VltBattleCreature] = []
var _names: Dictionary[String, String] = {}


func _init(
	from: VltBattleView,
	onto: BattleStage,
	registry: VltEffectRegistry,
	moves: Dictionary[String, VltMoveDefinition] = {},
	species: Dictionary[String, VltSpecies] = {},
	own_party: Array[VltBattleCreature] = []
) -> void:
	view = from
	stage = onto
	_registry = registry
	_moves = moves
	_species = species
	_party = own_party
	_rename()


## Plays every event in order, and returns when the last one has been seen.
func play(events: Array[VltLogEvent]) -> void:
	for event: VltLogEvent in events:
		await one(event)


## One event: advance what is known, say what it is, then show it.
##
## The view moves first. A clip that played before the view knew about it would
## animate a health bar that had not dropped yet, which reads as a stutter and is
## really an ordering mistake.
##
## **The line comes before the clips**, and the bars after. An attack announced
## after it had already landed put a whole sentence between the blow and the
## flinch — the actor swung, the text explained it, and only then did the target
## react. Said first, the sentence is what the animation illustrates.
##
## It costs one case: a faint reads its line as the creature falls rather than
## after. Naming the events that announce and the events that report would be a
## third table beside the clips and the lines, and one late line is cheaper than
## a third vocabulary.
func one(event: VltLogEvent) -> void:
	_warn_if_unknown(event)

	view.advance(event, _registry, _species, _party)
	_rename()

	var line: BattleLines.Line = BattleLines.of(event, _names)
	if not line.is_silent():
		await stage.say(line)

	for cue: BattleClips.Cue in BattleClips.of(event, _moves):
		await stage.play(cue.at, cue.slot)

	await stage.refresh(view)


## What to call whoever is standing where, rebuilt after every event because a
## switch changes it. Species names are translated at the point of use, so the
## table holds keys rather than sentences.
func _rename() -> void:
	_names = {}
	for row: Array[VltBattleView.Combatant] in [view.mine, view.theirs]:
		for seat: VltBattleView.Combatant in row:
			if seat.present and seat.reference != null:
				_names["%d,%d" % [seat.reference.side, seat.reference.slot]] = tr(
					BattleLines.species_key(seat.species_id)
				)


## An unrecognised event is played as far as it can be and reported, never
## fatal. A reader that failed here would make adding a mechanic a UI change,
## every time (spec 17, section 3).
func _warn_if_unknown(event: VltLogEvent) -> void:
	if not BattleClips.of(event, _moves).is_empty():
		return
	if not BattleLines.of(event, _names).is_silent():
		return
	if SILENT_KINDS.has(event.kind()):
		return
	push_warning("the battle reader has nothing to show for \"%s\"" % event.kind())
