class_name BattleScreen
extends Node3D

## A battle you can watch (spec 17).
##
## Rough on purpose. The layout, the camera and the look of the HUD are
## specified nowhere, so nothing here is an art direction — it is the least
## thing that puts a real battle on screen, built in code so that its diff is
## readable and its replacement is a deletion.
##
## **This holds the battle state, and that is correct.** Whoever owns a battle
## legitimately has it; the lint of decision 0049 seals the *reader*, which is
## the part that must never reach past its filter. The boundary is here, at the
## seam, rather than a rule the whole game has to remember.

const PLAYER: int = 0
const FOE: int = 1
const LEVEL: int = 20
const SEED: int = 20260910

## Named so anything outside can find it without reaching into a field. A node
## name is a contract; a private variable is not.
const MENU_NAME: String = "MoveMenu"

## Emitted once, when nobody on one side is still standing. The argument says
## which side won, because a caller that had to work that out from the state
## would be reaching past the seam this whole screen defends.
signal ended(player_won: bool)

## Set before adding this to the tree. Empty means the screen builds its own
## battle, which is what makes it runnable on its own — a screen you cannot open
## without a world behind it is a screen nobody debugs.
var incoming_player: Array[VltBattleCreature] = []
var incoming_foe: Array[VltBattleCreature] = []

var _library: ContentLibrary
var _registry: VltEffectRegistry
var _engine: VltTurnEngine
var _decider: VltSeededDecider
var _state: VltBattleState
var _reader: BattleLogReader
var _stage: BattleScreenStage

var _message: Label
var _menu: VBoxContainer
var _busy: bool = false


func _ready() -> void:
	_library = ContentLibrary.load_all()
	_registry = _effects()
	_engine = VltTurnEngine.new(_library.moves, _library.chart, _registry)
	_decider = VltSeededDecider.new(SEED)

	_build_interface()
	_start()


static func _effects() -> VltEffectRegistry:
	var registry: VltEffectRegistry = VltEffectRegistry.new()
	registry.register(VltBurn.define())
	registry.register(VltReflect.define())
	return registry


## What this side can see. The only way out of here — nothing hands over the
## state, which is the seam decision 0049 draws.
func view() -> VltBattleView:
	return _reader.view


## True while a turn is playing back. Offered because a caller that sent a
## second command mid-turn would meet an engine that had consumed the first.
func is_busy() -> bool:
	return _busy


## Play at once rather than at a pace. What holding the button does, offered
## publicly because a caller driving a battle from outside — a test, or a fast
## forward the player asked for — needs the same thing the key does.
func skip(on: bool) -> void:
	_stage.skip = on


## Plays one exchange, and returns when the log has been seen. Public because
## driving a battle from outside is what a screen is for.
func take_turn(move_index: int) -> void:
	await _take_turn(move_index)


# --- the battle --------------------------------------------------------------


func _start() -> void:
	_state = VltBattleState.create(1)

	var parties: Array = [
		incoming_player if not incoming_player.is_empty() else _demo_party(PLAYER),
		incoming_foe if not incoming_foe.is_empty() else _demo_party(FOE),
	]

	for side: int in range(VltBattleState.SIDE_COUNT):
		for creature: Variant in parties[side]:
			@warning_ignore("unsafe_cast")
			_state.sides[side].party.append(creature as VltBattleCreature)
		_state.sides[side].slots[0].occupy(0)

	var opening: VltBattleView = VltBattleView.of(_state, _registry, PLAYER)
	_reader = BattleLogReader.new(
		opening, _stage, _registry, _library.moves, _library.species,
		_state.sides[PLAYER].party
	)

	_stage.refresh(opening)
	_offer_moves()


## What the screen makes when nobody handed it a battle. Sorted, so the two
## sides are the same two creatures on every run — a screen that shuffled its
## roster would make a bug hard to reproduce for no gain.
func _demo_party(side: int) -> Array[VltBattleCreature]:
	var roster: Array[String] = []
	for id: String in _library.species.keys():
		roster.append(id)
	roster.sort()

	var party: Array[VltBattleCreature] = []
	party.append(_born(_library.species[roster[side % roster.size()]]))
	return party


func _born(species: VltSpecies) -> VltBattleCreature:
	return VltBirth.at_level(
		species,
		LEVEL,
		_library.natures,
		_library.moves,
		_library.curves[species.growth_rate],
		VltSeededGenerationDecider.new(SEED + species.id.hash())
	)


## One exchange: the player's chosen move, the AI's answer, then the log played
## back through the reader.
func _take_turn(move_index: int) -> void:
	if _busy:
		return
	_busy = true
	_menu.hide()

	var commands: Array[VltCommand] = [
		VltCommand.use_move(VltSlotRef.at(PLAYER, 0), move_index, VltSlotRef.at(FOE, 0)),
		_foe_command(),
	]

	var outcome: VltTurnOutcome = _engine.resolve(_state, commands, _decider)
	_state = outcome.state

	await _reader.play(outcome.log.for_viewer(PLAYER).events)

	_busy = false
	if _finished():
		_message.text = "The battle is over."
		ended.emit(_standing(PLAYER))
		return
	_offer_moves()


## The AI plays the other side, against the same filtered view a player would
## get. It does not know it is not one (spec 17, section 7).
##
## Its policy is scripted rather than drawn: a screen that hesitated differently
## on each run would make anything seen here impossible to reproduce.
func _foe_command() -> VltCommand:
	return VltBattleAi.choose(
		VltBattleView.of(_state, _registry, FOE),
		0,
		_library.moves,
		_library.species,
		_library.chart,
		VltBattleAi.plain(),
		VltScriptedPolicyDecider.new(true, 0)
	)


func _finished() -> bool:
	return not _standing(PLAYER) or not _standing(FOE)


func _standing(side: int) -> bool:
	var creature: VltBattleCreature = _state.creature_at(VltSlotRef.at(side, 0))
	return creature != null and not creature.is_fainted()


# --- what it looks like ------------------------------------------------------


func _build_interface() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	_message = _label(layer, Vector2(24, 24), 28)
	_message.text = "..."

	_menu = VBoxContainer.new()
	_menu.name = MENU_NAME
	_menu.position = Vector2(24, 320)
	layer.add_child(_menu)

	_stage = BattleScreenStage.new(get_tree(), _message)
	for side: int in range(VltBattleState.SIDE_COUNT):
		var at: VltSlotRef = VltSlotRef.at(side, 0)
		var top: float = 90.0 + float(side) * 70.0
		var title: Label = _label(layer, Vector2(24, top), 20)
		var bar: ProgressBar = ProgressBar.new()
		bar.position = Vector2(24, top + 28)
		bar.size = Vector2(280, 16)
		bar.max_value = VltLogEvent.REDUCED_SCALE
		bar.show_percentage = false
		layer.add_child(bar)

		var body: Node3D = Node3D.new()
		body.position = Vector3(float(side) * 3.0 - 1.5, 0, 0)
		add_child(body)
		_stage.seat(at, title, bar, body)


static func _label(into: Node, at: Vector2, size: int) -> Label:
	var label: Label = Label.new()
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	into.add_child(label)
	return label


func _offer_moves() -> void:
	for child: Node in _menu.get_children():
		child.queue_free()

	var creature: VltBattleCreature = _state.creature_at(VltSlotRef.at(PLAYER, 0))
	if creature == null:
		return

	for index: int in range(creature.moves.size()):
		var slot: VltMoveSlot = creature.moves[index]
		var button: Button = Button.new()
		button.text = "%s   %d/%d" % [
			slot.move_id, slot.pp, _library.moves[slot.move_id].max_pp
		]
		button.disabled = slot.pp <= 0
		button.pressed.connect(_take_turn.bind(index))
		_menu.add_child(button)

	_menu.show()


## Held down to skip. The reader has no opinion about this — it always awaits,
## and a skipping stage simply stops taking time.
func _process(_delta: float) -> void:
	_stage.skip = Input.is_key_pressed(KEY_SPACE)
