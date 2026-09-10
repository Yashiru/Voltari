class_name WorldSandbox
extends Node3D

## Somewhere to walk (specs 14, 15 and 18).
##
## The scene that assembles what the tests have been proving in pieces: a map, a
## walker, the quantiser, encounters, events, flags and a save. Every part of it
## already had tests; none of them had a place to meet.
##
## Rough on purpose, like the battle screen. Nothing here is a camera direction
## or a HUD design, and its replacement should be a deletion.

const MAPS: Dictionary[String, String] = {
	"starter_field": "res://game/maps/starter_field.tscn",
	"starter_cave": "res://game/maps/starter_cave.tscn",
}

const START_MAP: String = "starter_field"
const START_CELL: Vector2i = Vector2i(1, 1)
const SAVE_PATH: String = "user://sandbox.json"

## How long one cell takes. The pace lives here, the way it lives in the battle
## stage — nothing below has an opinion about it.
const STEP_SECONDS: float = 0.16
const CELL: float = 2.0
const BATTLE_SCENE: String = "res://game/scenes/battle/battle_screen.tscn"
const STARTER_LEVEL: int = 12

var _settings: VltSettings
var _library: ContentLibrary
var _tables: Dictionary[String, VltEncounterTable] = {}
var _species: Dictionary[String, VltSpecies] = {}
var _flags: VltQuestFlags = VltQuestFlags.new()
var _encounters: VltSeededEncounterDecider

var _map: VltWorldMap = null
var _walker: VltGridWalker
var _held: VltStepIntent.Held = VltStepIntent.Held.new()
var _cooldown: float = 0.0

var _run: VltEventRun = null
var _battle: BattleScreen = null

## The player's own creatures. They carry their wounds between battles, which is
## the whole reason they are held here rather than made when one starts.
var _party: Array[VltBattleCreature] = []

## What is left to throw. There is no inventory and no spec for one, so this is
## a count in the seam until there is somewhere better for it to live.
var _bag: Dictionary[String, int] = {"basic_ball": 5, "better_ball": 2}
var _message: Label
var _hint: Label
var _stick: TouchStick
var _camera: Camera3D
var _body: Node3D


func _ready() -> void:
	Translations.install()
	_settings = AppliedSettings.install()
	var library: ContentLibrary = ContentLibrary.load_all()
	_species = library.species
	_tables = VltEncounterTableLoader.all_from_payload(
		VltContentPayloads.read_indexed("res://content/generated/encounters")
	)
	_encounters = VltSeededEncounterDecider.new(int(Time.get_unix_time_from_system()))

	_library = library
	# Sorted, so a new game always starts with the same creature. A starter that
	# depended on dictionary order would differ between runs for no reason.
	var roster: Array[String] = []
	for id: String in library.species.keys():
		roster.append(id)
	roster.sort()
	# Two, so that switching is reachable at all. One creature makes every
	# battle a fight to the end whether or not that was the design.
	_party = [
		_born(roster[0], STARTER_LEVEL),
		_born(roster[mini(1, roster.size() - 1)], STARTER_LEVEL - 2),
	]

	_build_interface()
	_enter(START_MAP, START_CELL, VltFacing.Direction.SOUTH)
	_load_if_present()


## Where the walker is standing, and on which map. The way in for anything
## outside — a scene above, or a test.
func cell() -> Vector2i:
	return _walker.cell


func map_id() -> String:
	return "" if _map == null else _map.map_id


func flags() -> VltQuestFlags:
	return _flags


## True while an event is playing, which is when nothing else may happen.
func in_event() -> bool:
	return _run != null


## One step, bypassing the stick. Public because driving the world from outside
## is what a sandbox is for.
func walk(direction: VltFacing.Direction) -> void:
	_step(direction)


## Turn without moving — what a flick does, and what you do before reading a
## sign you cannot walk into.
func face(direction: VltFacing.Direction) -> void:
	_walker.facing = direction


func interact() -> void:
	_interact()


## True while a battle is on top of the world. The world keeps everything it
## had; nothing is saved and reloaded to cross the seam.
func in_battle() -> bool:
	return _battle != null


## The player's own creatures, carrying their wounds between battles.
func party() -> Array[VltBattleCreature]:
	return _party


## What is left to throw.
func bag() -> Dictionary[String, int]:
	return _bag


## Starts a battle against a given species, bypassing the grass. Public because
## the handoff is the interesting part and waiting for a random encounter is a
## poor way to exercise it.
func meet(species_id: String, level: int) -> void:
	_meet(VltEncounter.Outcome.new(species_id, level))


func save_now() -> void:
	_save()


func load_now() -> void:
	_load_if_present()


# --- walking -----------------------------------------------------------------


func _process(delta: float) -> void:
	_cooldown = maxf(0.0, _cooldown - delta)

	if _battle != null:
		return
	if _run != null:
		_advance_event()
		return

	var stick: Vector2 = _stick.stick()
	if not _stick.is_held():
		stick = VltStepIntent.from_keys(
			Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W),
			Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S),
			Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D),
			Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A)
		)

	var intent: VltStepIntent.Step = VltStepIntent.of(stick, _held, delta)
	if not intent.wanted:
		return

	# A flick turns without moving, which is how you face a sign you are about
	# to read.
	_walker.facing = intent.direction
	if intent.walk and _cooldown <= 0.0:
		_step(intent.direction)


func _step(direction: VltFacing.Direction) -> void:
	var step: VltGridWalker.Step = _walker.step(direction)
	_cooldown = STEP_SECONDS
	_place_body()

	if step.warp != null:
		_enter(step.warp.to_map, step.warp.to_cell, step.warp.to_facing)
		return
	if step.event != null:
		_begin(step.event)
		return
	if step.encounter != null:
		_meet(step.encounter)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return

	match (event as InputEventKey).keycode:
		KEY_SPACE, KEY_ENTER:
			if _run == null:
				_interact()
		KEY_F5:
			_save()
		KEY_F9:
			_load_if_present()


func _interact() -> void:
	var event: VltEvent = _walker.interact()
	if event == null:
		_message.text = "Nothing there."
		return
	_begin(event)


# --- meeting something -------------------------------------------------------


## The handoff. The world produces a species and a level and stops there
## (spec 14, section 5); this is the first thing that takes it further.
func _meet(outcome: VltEncounter.Outcome) -> void:
	_message.text = "A wild %s appeared!" % tr(
		BattleLines.species_key(outcome.species_id)
	)

	var wild: VltBattleCreature = _born(outcome.species_id, outcome.level)

	var packed: PackedScene = load(BATTLE_SCENE)
	_battle = packed.instantiate() as BattleScreen
	_battle.incoming_player = _party
	_battle.bag = _bag
	_battle.incoming_foe = [wild] as Array[VltBattleCreature]
	_battle.ended.connect(_battle_ended)

	# The world stays in the tree, holding everything: position, flags, the party
	# and its wounds. Nothing is saved and reloaded to cross this seam.
	_show_world(false)
	add_child(_battle)


## Every map, kept so that "the nearest rest point" can be answered without
## loading the world twice.
func _all_maps() -> Dictionary[String, VltWorldMap]:
	var loaded: Dictionary[String, VltWorldMap] = {}
	for id: String in MAPS:
		if _map != null and _map.map_id == id:
			loaded[id] = _map
			continue
		var packed: PackedScene = load(MAPS[id])
		loaded[id] = packed.instantiate() as VltWorldMap
	return loaded


## Losing sends the party to the nearest rest point and heals it.
##
## The healing is the part to be honest about: it is here because nothing else
## can heal, and a defeat that left the party hurt would be a defeat the player
## could not recover from at all. It stops being right the day an item or a
## service exists (decision 0053).
func _recover() -> void:
	var maps: Dictionary[String, VltWorldMap] = _all_maps()
	var found: VltRestPoint.Found = VltRestPoint.nearest(maps, map_id(), _walker.cell)

	for id: String in maps:
		if maps[id] != _map:
			maps[id].free()

	for creature: VltBattleCreature in _party:
		creature.current_hp = creature.max_hp()

	if found == null:
		# The validator refuses content that can reach none, so this is a world
		# somebody built by hand. Standing back up where they fell beats being
		# stuck.
		_message.text = "You came to where you fell."
		return

	_enter(found.map_id, found.cell, found.facing)
	_message.text = "You came to at the camp."


func _battle_ended(player_won: bool) -> void:
	# Read before the screen goes: it holds what the battle was worth, and the
	# creatures it changed are the ones the world is still carrying.
	var summary: String = "Your creature fainted."
	if _battle != null and player_won:
		summary = _worth(_battle.awards())

	if _battle != null:
		_battle.queue_free()
		_battle = null

	_show_world(true)

	if not player_won:
		_recover()
		return
	_message.text = summary


## What just happened to the party, in one line. The awards carry more than
## this — offered moves in particular — and nothing here asks the question,
## because the screen that would put it to the player does not exist
## (spec 10, section 7).
static func _worth(awards: Array[VltPostBattle.Award]) -> String:
	if awards.is_empty():
		return "You won."

	var parts: Array[String] = []
	for award: VltPostBattle.Award in awards:
		var line: String = "+%d XP" % award.experience
		if award.level_after > award.level_before:
			line += " → level %d" % award.level_after
		if not award.evolved_into.is_empty():
			line += " → evolved"
		parts.append(line)

	return "You won.  " + "  ".join(parts)


func _show_world(visible_now: bool) -> void:
	if _map != null:
		_map.visible = visible_now
	_body.visible = visible_now
	_camera.current = visible_now
	_stick.visible = visible_now
	_hint.visible = visible_now


func _born(species_id: String, level: int) -> VltBattleCreature:
	var species: VltSpecies = _library.species[species_id]
	return VltBirth.at_level(
		species,
		level,
		_library.natures,
		_library.moves,
		_library.curves[species.growth_rate],
		VltSeededGenerationDecider.new(_encounters.encounter_level(1, 1 << 20))
	)


# --- events ------------------------------------------------------------------


func _begin(event: VltEvent) -> void:
	_run = VltEventRun.of(event, _flags)
	_advance_event()


## One event at a time, advanced by a key. The run suspends rather than awaiting
## (decision 0044), so driving it is a loop and not a coroutine.
func _advance_event() -> void:
	_run.advance()

	if _run.is_finished():
		_run = null
		_hint.text = _controls()
		return

	var request: VltEventRequest = _run.request()
	if request == null:
		return
	_message.text = tr(request.line_id)
	_hint.text = "space to continue"

	if Input.is_action_just_pressed("ui_accept"):
		_run.resume()


# --- maps --------------------------------------------------------------------


func _enter(into: String, at: Vector2i, facing: VltFacing.Direction) -> void:
	if _map != null:
		_map.queue_free()

	var packed: PackedScene = load(MAPS[into])
	_map = packed.instantiate() as VltWorldMap
	add_child(_map)

	_walker.map = _map
	_walker.place(at, facing)
	_place_body()
	_message.text = into

	# Arriving on a map is one of the three moments an event may fire
	# (decision 0043).
	var arrival: VltEvent = _map.event_at(at, VltEvent.Trigger.ENTER_MAP)
	if arrival != null:
		_begin(arrival)


func _place_body() -> void:
	var where: Vector3 = Vector3(float(_walker.cell.x) * CELL, 0.8, float(_walker.cell.y) * CELL)
	_body.position = where
	_camera.position = where + Vector3(0, 9, 7)
	_camera.look_at(where)


# --- the save ----------------------------------------------------------------
#
# Two sections, written by two systems that know nothing about each other, into
# one document (spec 13, section 2). This is the first place both exist at once.


func _sections() -> Array[VltSaveSection]:
	var where: VltWorldSaveSection = VltWorldSaveSection.new(_walker)
	var quest: VltQuestFlagsSection = VltQuestFlagsSection.new(_flags)
	var creatures: VltPartySaveSection = VltPartySaveSection.new(_party)
	var all: Array[VltSaveSection] = [where, quest, creatures]
	return all


func _save() -> void:
	var written: bool = VltSaveStore.write(SAVE_PATH, VltSaveCodec.write(_sections()))
	_message.text = "Saved." if written else "Could not save."


func _load_if_present() -> void:
	if not VltSaveStore.exists(SAVE_PATH):
		return

	var where: VltWorldSaveSection = VltWorldSaveSection.new()
	var quest: VltQuestFlagsSection = VltQuestFlagsSection.new(_flags)
	# Read in place, so the party the world walks around with is the one that
	# comes back — nothing has to be assigned afterwards and forgotten.
	var creatures: VltPartySaveSection = VltPartySaveSection.new(_party)
	var sections: Array[VltSaveSection] = [where, quest, creatures]
	var report: VltSaveCodec.Report = VltSaveCodec.read(
		VltSaveStore.read(SAVE_PATH), sections
	)

	if not MAPS.has(where.map_id):
		_message.text = "Saved on a map this build does not have."
		return

	_enter(where.map_id, where.cell, where.facing)
	_message.text = "Loaded." if report.complete() else "Loaded what could be read."


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		save_on_background()


## On a phone this is the ordinary way a session ends: the application is put
## away and later killed. Returns whether it wrote, because "it refused" and "it
## failed" are different things and only one of them is fine.
##
## **Two refusals, and both are older than this function.** Not mid-event: a
## half-run event has set no flags and a save now records a world nothing can
## resume (decision 0044). Not mid-battle: a save never holds battle state
## (spec 13, section 6), and the battle would be lost on reload anyway — which
## is accepted, but losing the walk that led to it is not.
##
## The second guard was missing and nothing noticed, because the only way to
## meet it is to be interrupted at exactly the wrong moment.
func save_on_background() -> bool:
	if _walker == null or _run != null or _battle != null:
		return false
	return VltSaveStore.write(SAVE_PATH, VltSaveCodec.write(_sections()))


# --- what it looks like ------------------------------------------------------


func _build_interface() -> void:
	_camera = Camera3D.new()
	add_child(_camera)

	var sun: DirectionalLight3D = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	add_child(sun)

	_walker = VltGridWalker.new()
	_walker.tables = _tables
	_walker.encounter_decider = _encounters
	add_child(_walker)

	_body = MeshInstance3D.new()
	var pill: CapsuleMesh = CapsuleMesh.new()
	pill.radius = 0.4
	pill.height = 1.6
	(_body as MeshInstance3D).mesh = pill
	add_child(_body)

	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	_message = Label.new()
	_message.position = Vector2(24, 24)
	_message.add_theme_font_size_override("font_size", 24)
	layer.add_child(_message)

	_hint = Label.new()
	_hint.position = Vector2(24, 60)
	_hint.text = _controls()
	layer.add_child(_hint)

	_stick = TouchStick.new()
	_stick.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stick.mouse_filter = Control.MOUSE_FILTER_PASS
	layer.add_child(_stick)


static func _controls() -> String:
	return "arrows or drag to walk  ·  space to interact  ·  F5 save  ·  F9 load"
