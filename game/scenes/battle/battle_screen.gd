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

## How tall a creature is drawn. The manifests declare it and `CreatureBody`
## enforces it, so the staging can rely on it rather than measuring.
const CREATURE_HEIGHT: float = 1.0

## Emitted once, when nobody on one side is still standing. The argument says
## which side won, because a caller that had to work that out from the state
## would be reaching past the seam this whole screen defends.
signal ended(player_won: bool)

## Set before adding this to the tree. Empty means the screen builds its own
## battle, which is what makes it runnable on its own — a screen you cannot open
## without a world behind it is a screen nobody debugs.
var incoming_player: Array[VltBattleCreature] = []
var incoming_foe: Array[VltBattleCreature] = []

## Ball id to how many are left. There is no inventory system and no spec for
## one, so this is the seam holding a count until there is somewhere better.
var bag: Dictionary[String, int] = {}

## The source of chance. Set before adding this to the tree; absent means a
## seeded one of its own.
##
## Offered because a battle worth reproducing is a battle whose randomness the
## caller chose — a replay needs exactly this, and so does any test that has to
## make an unlikely thing happen rather than wait for it.
var incoming_decider: VltDecider = null

var _library: ContentLibrary
var _registry: VltEffectRegistry
var _engine: VltTurnEngine
var _decider: VltDecider
var _state: VltBattleState
var _reader: BattleLogReader
var _stage: BattleScreenStage

## The position the battle opened from, and everything that has happened since.
## Both are what the post-battle pipeline needs: experience is earned by whoever
## faced what fell, and only the log knows who that was (spec 10, section 4).
var _settings: VltSettings
var _manifests: Dictionary[String, PresentationEntry] = {}
var _balls: Dictionary[String, float] = {}
var _initial: VltBattleState
var _history: VltBattleLog = VltBattleLog.new()

## What the battle was worth, once it is over. Empty until then.
var _awards: Array[VltPostBattle.Award] = []

## Moves a creature earned and has no room for, waiting to be put to the player.
## Each is a party index and a move id; the pair is what a choice needs, and
## keeping them together is what stops the wrong creature learning something.
## Evolutions to announce, each a species it was and one it became. They have
## already happened — the pipeline applies one whose trigger is satisfied
## (spec 10, section 8) — so this is a moment, not a question. Whether it could
## be refused is a design question spec 10 names and leaves open.
var _evolutions: Array[Array] = []
var _offers: Array[Array] = []
var _won: bool = false

## Slots the engine is waiting on. A turn suspends when somebody falls and a
## replacement has to be chosen (decision 0012), and the caller drives it — so
## this is what "the caller" means.
var _awaiting: Array[VltSlotRef] = []
var _replacements: Array[VltCommand] = []

var _message: Label
var _menu: VBoxContainer
var _busy: bool = false


func _ready() -> void:
	Translations.install()
	_settings = AppliedSettings.install()
	_library = ContentLibrary.load_all()
	_manifests = PresentationLoader.all_from_payload(
		VltContentPayloads.read_indexed("res://content/generated/presentation")
	)
	_balls = VltItemLoader.ball_multipliers(
		VltContentPayloads.read_indexed("res://content/generated/items")
	)
	_registry = _effects()
	_engine = VltTurnEngine.new(_library.moves, _library.chart, _registry)
	_decider = incoming_decider if incoming_decider != null else VltSeededDecider.new(SEED)

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

	_initial = _state.clone()
	var opening: VltBattleView = VltBattleView.of(_state, _registry, PLAYER)
	_reader = BattleLogReader.new(
		opening, _stage, _registry, _library.moves, _library.species,
		_state.sides[PLAYER].party
	)

	for side: int in range(VltBattleState.SIDE_COUNT):
		_stage.dress(VltSlotRef.at(side, 0), _manifest_for(side))

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
	await _take_turn_with(
		VltCommand.use_move(VltSlotRef.at(PLAYER, 0), move_index, VltSlotRef.at(FOE, 0))
	)


## One exchange, whatever the player chose to do with their half of it. A throw
## and a move are the same shape to everything below here, which is the point of
## commands being data (spec 03).
func _take_turn_with(mine: VltCommand) -> void:
	if _busy:
		return
	_busy = true
	_menu.hide()

	var commands: Array[VltCommand] = [mine, _foe_command()]

	await _resolve(commands)


## Runs a turn and whatever it asks for afterwards.
##
## A turn does not always finish: when somebody falls, resolution suspends and
## says which slots need a replacement (decision 0012). The caller supplies them
## and calls again — so this loop is the caller, and it exists here rather than
## anywhere lower because choosing is the player's, not the engine's.
func _resolve(commands: Array[VltCommand]) -> void:
	var outcome: VltTurnOutcome = _engine.resolve(_state, commands, _decider)

	if outcome.status == VltTurnOutcome.Status.REJECTED:
		# The engine refused the command rather than playing it. Reported rather
		# than swallowed: it means the screen offered something impossible.
		push_warning("the engine refused a turn: %s" % outcome.rejection)
		_busy = false
		_offer_moves()
		return

	_state = outcome.state
	for event: VltLogEvent in outcome.log.events:
		_history.append(event)
	await _reader.play(outcome.log.for_viewer(PLAYER).events)

	if outcome.status == VltTurnOutcome.Status.NEEDS_INPUT:
		_awaiting = outcome.request_slots.duplicate()
		_replacements = []
		_ask_replacement()
		return

	_busy = false
	_redress()

	if _finished():
		_settle()
		return
	_offer_moves()


## Puts the replacement question, or answers the turn once every slot has one.
##
## The other side answers itself. A player waiting for an opponent to choose is
## a player waiting for nothing.
func _ask_replacement() -> void:
	while not _awaiting.is_empty() and _awaiting[0].side != PLAYER:
		var theirs: VltSlotRef = _awaiting.pop_front()
		_replacements.append(VltCommand.switch_to(theirs, _first_ready(theirs.side)))

	if _awaiting.is_empty():
		await _resolve(_replacements)
		return

	var mine: VltSlotRef = _awaiting[0]
	_message.text = "Who takes over?"
	_show_party(mine, true)


## Chooses a replacement, or switches voluntarily when nothing was asked for.
func choose_creature(party_index: int) -> void:
	if not _awaiting.is_empty():
		var mine: VltSlotRef = _awaiting.pop_front()
		_replacements.append(VltCommand.switch_to(mine, party_index))
		_ask_replacement()
		return

	await _take_turn_with(VltCommand.switch_to(VltSlotRef.at(PLAYER, 0), party_index))


## The party indices this side could send out: not fainted, not already on the
## field. Public because a menu is not the only thing that will ask.
func ready_creatures(side: int = PLAYER) -> PackedInt32Array:
	var ready: PackedInt32Array = PackedInt32Array()
	var out: int = _state.slot_at(VltSlotRef.at(side, 0)).occupant

	for index: int in range(_state.sides[side].party.size()):
		var creature: VltBattleCreature = _state.sides[side].party[index]
		if index != out and not creature.is_fainted():
			ready.append(index)
	return ready


func _first_ready(side: int) -> int:
	var ready: PackedInt32Array = ready_creatures(side)
	return 0 if ready.is_empty() else ready[0]


## Slots waiting on this side. Empty when nothing was asked for.
func awaiting_replacement() -> bool:
	return not _awaiting.is_empty()


func _show_party(_at: VltSlotRef, forced: bool) -> void:
	for child: Node in _menu.get_children():
		child.queue_free()

	for index: int in ready_creatures(PLAYER):
		var creature: VltBattleCreature = _state.sides[PLAYER].party[index]
		var button: Button = Button.new()
		button.text = "%s   %d/%d" % [
			tr(BattleLines.species_key(creature.species_id)),
			creature.current_hp,
			creature.max_hp(),
		]
		button.pressed.connect(choose_creature.bind(index))
		_menu.add_child(button)

	if not forced:
		var back: Button = Button.new()
		back.text = "back"
		back.pressed.connect(_offer_moves)
		_menu.add_child(back)

	_menu.show()


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


## What the battle was worth. Run once, when it is over, over the whole log
## rather than one turn's — experience is earned by whoever was facing the
## creature that fell, and a single turn does not know.
##
## The creatures are the caller's own objects, so what this changes is changed
## for good the moment it returns. That is what makes progress stick without
## anything being copied back.
## Whoever was caught, taken out of the side that owned them.
##
## The core vacates the slot and leaves the creature where it was: spec 11
## section 7 says where it goes next belongs to a party and box system, and
## there is none. So the seam decides, and it decides the simplest thing —
## straight into the party, no room check, because nothing describes a full one.
func _take_captured() -> void:
	for event: VltLogEvent in _history.events:
		var result: VltLogCaptureResult = event as VltLogCaptureResult
		if result == null or not result.captured:
			continue

		var side: int = result.target.side
		if side != PLAYER and result.party_index < _state.sides[side].party.size():
			_state.sides[PLAYER].party.append(
				_state.sides[side].party[result.party_index]
			)


func _settle() -> void:
	_take_captured()
	_won = _standing(PLAYER)
	var won: bool = _won

	if won:
		_awards = VltPostBattle.resolve(
			_initial,
			_history,
			_state,
			PLAYER,
			_library.species,
			_library.curves,
			_library.moves,
			false
		)

	for award: VltPostBattle.Award in _awards:
		if not award.evolved_into.is_empty():
			_evolutions.append([award.evolved_from, award.evolved_into])
		for move_id: String in award.offered:
			_offers.append([award.party_index, move_id])

	_message.text = _summary(won)
	_ask_next()


## The move being asked about right now, or empty.
##
## Not "the head of the queue": while an evolution is on screen there is a move
## waiting and nobody is being asked about it, and a caller that acted on the
## difference would answer a question that had not been put.
func offered_move() -> String:
	if not _evolutions.is_empty() or _offers.is_empty():
		return ""
	@warning_ignore("unsafe_cast")
	return _offers[0][1] as String


## Takes the offered move in place of the one in `slot`.
func learn_instead_of(slot: int) -> void:
	if _offers.is_empty():
		return

	@warning_ignore("unsafe_cast")
	var index: int = _offers[0][0] as int
	@warning_ignore("unsafe_cast")
	var move_id: String = _offers[0][1] as String
	_offers.pop_front()

	VltPostBattle.learn(
		_state.sides[PLAYER].party[index], move_id, slot, _library.moves
	)
	_ask_next()


## Leaves the four it has. Explicit rather than a timeout or a closed panel: a
## refusal the player made is not the same as a question nobody answered, and
## only one of them should be remembered as a decision.
func decline_offer() -> void:
	if _offers.is_empty():
		return
	_offers.pop_front()
	_ask_next()


## Puts the question, or finishes the battle when there is none left.
##
## `ended` waits for this. A world that took itself back while a creature was
## still being asked what to forget would answer for the player.
func _ask_next() -> void:
	# Evolutions first, because they change what a creature is called and the
	# question that follows names it.
	if not _evolutions.is_empty():
		_announce_evolution()
		return

	if _offers.is_empty():
		_menu.hide()
		_hand_back()
		ended.emit(_won)
		return

	@warning_ignore("unsafe_cast")
	var index: int = _offers[0][0] as int
	@warning_ignore("unsafe_cast")
	var move_id: String = _offers[0][1] as String
	var creature: VltBattleCreature = _state.sides[PLAYER].party[index]

	_message.text = "%s can learn %s. Forget which?" % [
		tr(BattleLines.species_key(creature.species_id)), move_id
	]

	for child: Node in _menu.get_children():
		child.queue_free()

	for slot: int in range(creature.moves.size()):
		var button: Button = Button.new()
		button.text = "forget %s" % creature.moves[slot].move_id
		button.pressed.connect(learn_instead_of.bind(slot))
		_menu.add_child(button)

	var keep: Button = Button.new()
	keep.text = "keep them all"
	keep.pressed.connect(decline_offer)
	_menu.add_child(keep)

	_menu.show()


## Shows one evolution and waits to be acknowledged. A moment rather than a
## line in a summary: it is the thing a player will remember from the battle.
func _announce_evolution() -> void:
	@warning_ignore("unsafe_cast")
	var was: String = _evolutions[0][0] as String
	@warning_ignore("unsafe_cast")
	var became: String = _evolutions[0][1] as String

	var line: BattleLines.Line = BattleLines.Line.new()
	line.key = "battle.evolved"
	line.arguments = {
		"creature": tr(BattleLines.species_key(was)),
		"into": tr(BattleLines.species_key(became)),
	}
	_message.text = BattleScreenStage.sentence(line)

	for child: Node in _menu.get_children():
		child.queue_free()

	var onward: Button = Button.new()
	onward.text = "continue"
	onward.pressed.connect(acknowledge_evolution)
	_menu.add_child(onward)
	_menu.show()


## The species a creature just became, or empty when nothing is being shown.
func evolution_shown() -> String:
	@warning_ignore("unsafe_cast")
	return "" if _evolutions.is_empty() else _evolutions[0][1] as String


func acknowledge_evolution() -> void:
	if _evolutions.is_empty():
		return
	_evolutions.pop_front()
	_ask_next()


## Puts the party that came out of the battle back into the array that went in.
##
## Decision 0011 makes a turn deep-copy its state on entry, so the caller's
## creatures are never touched — which is exactly right for the engine and
## exactly wrong for a party that is supposed to have learned something. The
## seam reconciles it, and this is the seam.
##
## The array is the shared thing, not the creatures in it. Replacing an element
## reaches the caller because they hold the same array.
func _hand_back() -> void:
	if incoming_player.is_empty():
		return

	var final: Array[VltBattleCreature] = _state.sides[PLAYER].party
	for index: int in range(final.size()):
		if index < incoming_player.size():
			incoming_player[index] = final[index]
		else:
			# Somebody new. A capture is the only way this happens today, and
			# appending is why the world sees it without being told.
			incoming_player.append(final[index])


func _summary(won: bool) -> String:
	if not won:
		return "Your creature fainted."
	if _awards.is_empty():
		return "You won."

	var parts: Array[String] = []
	for award: VltPostBattle.Award in _awards:
		var line: String = "%d XP" % award.experience
		if award.level_after > award.level_before:
			line += ", level %d" % award.level_after
		if not award.evolved_into.is_empty():
			line += ", became %s" % tr(BattleLines.species_key(award.evolved_into))
		if not award.offered.is_empty():
			# Nothing here asks the question: the choice is the player's and no
			# screen exists to put it to them (spec 10, section 7).
			line += ", could learn %s" % ", ".join(award.offered)
		parts.append(line)

	return "You won — " + "  ·  ".join(parts)


## The manifest for whoever is standing on a side, or null when the species has
## none. Null is ordinary: a creature with no manifest shows a stand-in.
## Called after every turn, because a switch and a capture both change who is
## standing there and neither says so in a way a seat could notice.
func _redress() -> void:
	for side: int in range(VltBattleState.SIDE_COUNT):
		_stage.dress(VltSlotRef.at(side, 0), _manifest_for(side))


func _manifest_for(side: int) -> PresentationEntry:
	var creature: VltBattleCreature = _state.creature_at(VltSlotRef.at(side, 0))
	if creature == null:
		return null
	return _manifests.get(creature.species_id)


## What the battle was worth, for whoever handed it a party. Empty until it is
## over, and empty when it was lost.
func awards() -> Array[VltPostBattle.Award]:
	return _awards


## Two different endings, and collapsing them is a mistake worth naming.
##
## A side **runs out**: nobody in its party is still standing. With one creature
## each that is the same sentence as "the active slot is empty", which is why
## reading the slot was right by accident until a party had two.
##
## Or somebody is **caught**, which ends the battle where it stands (spec 11,
## section 7) with the other side's party perfectly intact.
func _finished() -> bool:
	return _capture_landed() or not _standing(PLAYER) or not _standing(FOE)


func _capture_landed() -> bool:
	for event: VltLogEvent in _history.events:
		var result: VltLogCaptureResult = event as VltLogCaptureResult
		if result != null and result.captured:
			return true
	return false


func _standing(side: int) -> bool:
	for creature: VltBattleCreature in _state.sides[side].party:
		if not creature.is_fainted():
			return true
	return false


# --- what it looks like ------------------------------------------------------


func _build_interface() -> void:
	# On its own this scene's camera becomes current by being the only one. As a
	# child of the world it is not, and nothing was making it — which is
	# invisible to every headless test and the first thing anybody would see.
	_frame(_camera_or_new())

	var layer: CanvasLayer = CanvasLayer.new()
	add_child(layer)

	_message = _label(layer, Vector2(24, 24), 28)
	_message.text = "..."

	_menu = VBoxContainer.new()
	_menu.name = MENU_NAME
	_menu.position = Vector2(24, 320)
	layer.add_child(_menu)

	_stage = BattleScreenStage.new(get_tree(), _message)
	_stage.pace = _settings.text_speed
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

		var body: CreatureBody = CreatureBody.new()
		body.position = BattleStaging.seat(side)
		# Turned to look at whoever is opposite rather than to a fixed angle. Two
		# bodies each given the other's seat face each other whatever the seats
		# are, which is what stops this drifting when the staging is retuned.
		body.rotation.y = BattleStaging.yaw_towards(
			body.position, BattleStaging.seat(_other_than(side))
		)
		add_child(body)
		_stage.seat(at, title, bar, body)


## The other side. Two sides today, and this is the one place that would have to
## change if that ever stopped being true.
static func _other_than(side: int) -> int:
	return FOE if side == PLAYER else PLAYER


## The scene's camera, or one made on the spot.
##
## A screen with no camera renders nothing at all, and the scene file is a thing
## somebody can edit. Making one is cheaper than a black screen nobody can
## explain.
func _camera_or_new() -> Camera3D:
	for child: Node in get_children():
		if child is Camera3D:
			return child as Camera3D

	var made: Camera3D = Camera3D.new()
	made.name = "Camera3D"
	add_child(made)
	return made


## Points the camera at the pair, far enough back that both fit.
##
## Framed here rather than in the scene because it is framed *from* the seats and
## the camera's own field of view — a transform typed into a `.tscn` cannot
## follow either.
func _frame(camera: Camera3D) -> void:
	camera.make_current()
	camera.position = BattleStaging.eye(CREATURE_HEIGHT, camera.fov)
	camera.look_at(BattleStaging.target(CREATURE_HEIGHT))


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

	if not ready_creatures(PLAYER).is_empty():
		var swap: Button = Button.new()
		swap.text = "switch"
		swap.pressed.connect(_show_party.bind(VltSlotRef.at(PLAYER, 0), false))
		_menu.add_child(swap)

	for ball_id: String in _bag_order():
		var throw: Button = Button.new()
		throw.text = "throw %s   x%d" % [ball_id, bag[ball_id]]
		throw.pressed.connect(throw_ball.bind(ball_id))
		_menu.add_child(throw)

	_menu.show()


## Sorted, so the buttons are in the same order every time. A bag that reordered
## itself would make the wrong ball one mis-tap away.
func _bag_order() -> Array[String]:
	var ids: Array[String] = []
	for ball_id: String in bag:
		if bag[ball_id] > 0 and _balls.has(ball_id):
			ids.append(ball_id)
	ids.sort()
	return ids


## Throws a ball at whoever is opposite.
##
## The threshold is computed here and travels in the command: the core has a
## number and does not know what a ball is (decision 0032). Which means this is
## the only place that has to know how health, the species and a status combine.
func throw_ball(ball_id: String) -> void:
	if _busy or not _balls.has(ball_id) or bag.get(ball_id, 0) <= 0:
		return

	var at: VltSlotRef = VltSlotRef.at(FOE, 0)
	var target: VltBattleCreature = _state.creature_at(at)
	if target == null:
		return

	bag[ball_id] = bag[ball_id] - 1

	var rate: int = VltCapture.modified_rate(
		target.max_hp(),
		target.current_hp,
		_library.species[target.species_id].catch_rate,
		_balls[ball_id],
		VltCapture.status_multiplier(
			VltEffectDispatch.major_status(_state, _registry, at)
		)
	)

	_take_turn_with(
		VltCommand.throw_ball(
			VltSlotRef.at(PLAYER, 0), at, VltCapture.shake_threshold(rate)
		)
	)


## Held down to skip. The reader has no opinion about this — it always awaits,
## and a skipping stage simply stops taking time.
func _process(_delta: float) -> void:
	_stage.skip = Input.is_key_pressed(KEY_SPACE)
