extends GdUnitTestSuite

## The battle screen, run rather than looked at (spec 17).
##
## Not a test of what it looks like — nothing here has an art direction to check
## against. It is the smoke test that catches the failure a rough screen actually
## has: the content changed, or an engine signature moved, and the one thing that
## puts all of it together stopped working.
##
## It is also the only place the whole stack runs end to end: content, birth, the
## turn engine, the AI, the filtered log, the reader and a stage that draws.

const SCREEN: String = "res://game/scenes/battle/battle_screen.tscn"


func _screen() -> BattleScreen:
	var packed: PackedScene = load(SCREEN)
	assert_object(packed).override_failure_message("no scene at %s" % SCREEN).is_not_null()

	var screen: BattleScreen = auto_free(packed.instantiate() as BattleScreen)
	add_child(screen)
	return screen


func test_it_reaches_a_playable_position() -> void:
	var screen: BattleScreen = _screen()

	# Two creatures on the field, one of them ours, with moves to choose from.
	var view: VltBattleView = screen.view()
	assert_bool(view.mine[0].present).override_failure_message(
		"the screen came up with nobody on our side"
	).is_true()
	assert_bool(view.theirs[0].present).is_true()
	assert_int(view.mine[0].moves.size()).is_greater(0)


func test_the_menu_offers_exactly_the_moves_it_has() -> void:
	# A button per move, no more: a menu that offered a move a creature has not
	# got is a command the engine would reject at the worst moment.
	var screen: BattleScreen = _screen()
	var view: VltBattleView = screen.view()

	var menu: Node = screen.find_child(BattleScreen.MENU_NAME, true, false)
	assert_object(menu).override_failure_message("the screen has no move menu").is_not_null()

	var buttons: int = 0
	for child: Node in menu.get_children():
		if child is Button:
			buttons += 1

	assert_int(buttons).is_equal(view.mine[0].moves.size())


func test_a_turn_runs_the_whole_stack() -> void:
	# Content, birth, the engine, the AI, the filtered log, the reader, a stage.
	# If any of them has moved, this is where it shows.
	var screen: BattleScreen = _screen()
	screen._stage.skip = true

	var before: int = screen.view().turn
	await screen.take_turn(0)

	assert_int(screen.view().turn).override_failure_message(
		"a turn was taken and the view never heard about it"
	).is_greater(before)


func test_what_it_shows_of_the_opponent_stays_a_proportion() -> void:
	# Decision 0049 arriving on screen. The screen holds the state — it owns the
	# battle — and still shows only what the log said, because it draws from the
	# reader's view and nothing else.
	var screen: BattleScreen = _screen()
	screen._stage.skip = true
	await screen.take_turn(0)

	var theirs: VltBattleView.Combatant = screen.view().theirs[0]
	assert_bool(theirs.knows_exact_health()).override_failure_message(
		"the screen learned the opponent's exact health"
	).is_false()
	assert_int(theirs.health).is_between(0, VltLogEvent.REDUCED_SCALE)


func test_a_second_turn_cannot_start_while_one_is_playing() -> void:
	# The menu hides, but a held key or a double click would otherwise send two
	# commands into an engine that has already consumed the first.
	var screen: BattleScreen = _screen()
	screen._stage.skip = true

	screen._busy = true
	var turn: int = screen.view().turn
	await screen.take_turn(0)

	assert_int(screen.view().turn).override_failure_message(
		"a turn started while another was still playing"
	).is_equal(turn)


# --- being offered a move ----------------------------------------------------


## Puts an offer in front of the screen directly. Reaching a real one means
## levelling a creature past a learnset entry with four moves already, which is
## a long battle to arrange and a poor way to test a question.
func _offer(screen: BattleScreen, move_id: String) -> void:
	screen._won = true
	screen._offers = [[0, move_id]]
	screen._ask_next()


func test_an_offer_holds_the_battle_open() -> void:
	# A world that took itself back while a creature was still being asked what
	# to forget would be answering for the player.
	var screen: BattleScreen = _screen()
	var ended: Array[bool] = []
	screen.ended.connect(func(won: bool) -> void: ended.append(won))

	_offer(screen, "water_special")

	assert_str(screen.offered_move()).is_equal("water_special")
	assert_array(ended).override_failure_message(
		"the battle ended while a question was still on screen"
	).is_empty()


func test_taking_the_offer_replaces_the_slot_chosen() -> void:
	var screen: BattleScreen = _screen()
	var creature: VltBattleCreature = screen._state.sides[0].party[0]
	var kept: String = creature.moves[0].move_id

	_offer(screen, "water_special")
	screen.learn_instead_of(creature.moves.size() - 1)

	assert_str(creature.moves[creature.moves.size() - 1].move_id).is_equal("water_special")
	assert_str(creature.moves[0].move_id).override_failure_message(
		"a slot nobody chose was overwritten"
	).is_equal(kept)


func test_declining_leaves_the_four_it_has() -> void:
	# A refusal the player made is not the same as a question nobody answered,
	# and only one of them should be remembered as a decision.
	var screen: BattleScreen = _screen()
	var creature: VltBattleCreature = screen._state.sides[0].party[0]
	var before: int = creature.moves.size()

	_offer(screen, "water_special")
	screen.decline_offer()

	assert_int(creature.moves.size()).is_equal(before)
	for slot: VltMoveSlot in creature.moves:
		assert_str(slot.move_id).is_not_equal("water_special")


func test_answering_the_last_offer_ends_the_battle() -> void:
	var screen: BattleScreen = _screen()
	var ended: Array[bool] = []
	screen.ended.connect(func(won: bool) -> void: ended.append(won))

	_offer(screen, "water_special")
	screen.decline_offer()

	assert_array(ended).override_failure_message(
		"the battle never ended after the question was answered"
	).is_equal([true])


func test_two_offers_are_asked_one_at_a_time() -> void:
	# Each is a party index and a move together, which is what stops the wrong
	# creature learning the second one.
	var screen: BattleScreen = _screen()
	screen._won = true
	screen._offers = [[0, "water_special"], [0, "ghost_special"]]
	screen._ask_next()

	assert_str(screen.offered_move()).is_equal("water_special")
	screen.decline_offer()
	assert_str(screen.offered_move()).is_equal("ghost_special")
	screen.decline_offer()
	assert_str(screen.offered_move()).is_empty()


# --- an offer that came from a real battle -----------------------------------


## A creature one experience point short of the level at which it learns
## something, already holding four moves.
##
## Arranged rather than played into, because the alternative is a battle long
## enough to cross a level by accident — but arranged out of real content, so
## what reaches the queue is a real award and not a fixture.
func _about_to_learn(library: ContentLibrary) -> VltBattleCreature:
	var species: VltSpecies = library.species["placeholder_base"]
	var curve: PackedInt32Array = library.curves[species.growth_rate]

	var creature: VltBattleCreature = VltBirth.at_level(
		species, 12, library.natures, library.moves, curve,
		VltSeededGenerationDecider.new(11)
	)

	# It knows two at level 12 and learns a third at 13. Filling the last two
	# slots is what turns that third one from a gift into a question.
	for id: String in ["water_special", "ghost_special"]:
		if creature.moves.size() < VltBirth.MOVE_LIMIT:
			creature.moves.append(VltMoveSlot.create(id, library.moves[id].max_pp))

	assert_int(creature.moves.size()).is_equal(VltBirth.MOVE_LIMIT)
	creature.experience = curve[12] - 1
	return creature


func _weak_foe(library: ContentLibrary) -> VltBattleCreature:
	var species: VltSpecies = library.species["placeholder_base"]
	return VltBirth.at_level(
		species, 2, library.natures, library.moves,
		library.curves[species.growth_rate], VltSeededGenerationDecider.new(3)
	)


func test_a_real_battle_puts_a_real_offer_in_the_queue() -> void:
	# The join between settling up and asking. Every other test here posts an
	# offer by hand, so this is the only one that would notice an award whose
	# offered moves never reached the question.
	var library: ContentLibrary = ContentLibrary.load_all()

	var packed: PackedScene = load(SCREEN)
	var screen: BattleScreen = auto_free(packed.instantiate() as BattleScreen)
	screen.incoming_player = [_about_to_learn(library)] as Array[VltBattleCreature]
	screen.incoming_foe = [_weak_foe(library)] as Array[VltBattleCreature]
	add_child(screen)
	screen.skip(true)

	var guard: int = 0
	while screen.offered_move().is_empty() and guard < 30:
		await screen.take_turn(0)
		guard += 1

	assert_str(screen.offered_move()).override_failure_message(
		"a creature crossed the level it learns at and was never asked"
	).is_equal("inert_status")

	# And the award behind it says the same thing, which is what makes this the
	# join rather than two facts that happen to agree.
	var offered: PackedStringArray = PackedStringArray()
	for award: VltPostBattle.Award in screen.awards():
		offered.append_array(award.offered)
	assert_array(offered).contains(["inert_status"])


# --- throwing a ball ---------------------------------------------------------


func _with_bag(balls: Dictionary[String, int]) -> BattleScreen:
	var packed: PackedScene = load(SCREEN)
	var screen: BattleScreen = auto_free(packed.instantiate() as BattleScreen)
	screen.bag = balls
	add_child(screen)
	screen.skip(true)
	return screen


func test_a_throw_spends_a_ball() -> void:
	var screen: BattleScreen = _with_bag({"basic_ball": 2})
	await screen.throw_ball("basic_ball")
	assert_int(screen.bag["basic_ball"]).is_equal(1)


func test_an_empty_bag_throws_nothing() -> void:
	# The button is not offered, but a caller is not the button — and spending
	# a ball that is not there would go unnoticed until somebody counted.
	var screen: BattleScreen = _with_bag({"basic_ball": 0})
	var turn: int = screen.view().turn

	await screen.throw_ball("basic_ball")

	assert_int(screen.bag["basic_ball"]).is_equal(0)
	assert_int(screen.view().turn).override_failure_message(
		"a turn was spent throwing a ball nobody had"
	).is_equal(turn)


func test_a_ball_nobody_declared_is_refused() -> void:
	var screen: BattleScreen = _with_bag({"imaginary_ball": 3})
	await screen.throw_ball("imaginary_ball")
	assert_int(screen.view().turn).is_equal(0)


func test_a_throw_is_a_turn_like_any_other() -> void:
	# A ball and a move are the same shape to everything below the screen, which
	# is the point of commands being data.
	var screen: BattleScreen = _with_bag({"basic_ball": 5})
	var before: int = screen.view().turn

	await screen.throw_ball("basic_ball")

	assert_int(screen.view().turn).override_failure_message(
		"a throw did not advance the battle"
	).is_greater(before)


func test_a_throw_that_lands_takes_the_creature() -> void:
	# Every shake answered yes, because a probability is a poor thing to wait
	# for — and the best ball against a weakened target is still only about one
	# throw in three with this roster, which is not a test.
	var library: ContentLibrary = ContentLibrary.load_all()
	var packed: PackedScene = load(SCREEN)
	var screen: BattleScreen = auto_free(packed.instantiate() as BattleScreen)

	var species: VltSpecies = library.species["placeholder_base"]
	var wild: VltBattleCreature = VltBirth.at_level(
		species, 3, library.natures, library.moves,
		library.curves[species.growth_rate], VltSeededGenerationDecider.new(7)
	)
	wild.current_hp = 1

	var certain: VltScriptedDecider = VltScriptedDecider.new()
	certain.capture = VltScriptedDecider.Answer.ALWAYS

	screen.incoming_foe = [wild] as Array[VltBattleCreature]
	screen.bag = {"best_ball": 1}
	screen.incoming_decider = certain
	add_child(screen)
	screen.skip(true)

	await screen.throw_ball("best_ball")

	assert_bool(screen.view().theirs[0].present).override_failure_message(
		"every shake passed and the creature was still standing there"
	).is_false()


func test_a_caught_creature_joins_the_party_that_threw() -> void:
	# The seam's decision. The core vacates the slot and leaves the creature
	# where it was — spec 11 section 7 says where it goes next belongs to a
	# party and box system, and there is none.
	var library: ContentLibrary = ContentLibrary.load_all()
	var packed: PackedScene = load(SCREEN)
	var screen: BattleScreen = auto_free(packed.instantiate() as BattleScreen)

	var species: VltSpecies = library.species["placeholder_base"]
	var mine: VltBattleCreature = VltBirth.at_level(
		species, 20, library.natures, library.moves,
		library.curves[species.growth_rate], VltSeededGenerationDecider.new(1)
	)
	var wild: VltBattleCreature = VltBirth.at_level(
		species, 3, library.natures, library.moves,
		library.curves[species.growth_rate], VltSeededGenerationDecider.new(7)
	)
	wild.current_hp = 1

	var certain: VltScriptedDecider = VltScriptedDecider.new()
	certain.capture = VltScriptedDecider.Answer.ALWAYS

	var party: Array[VltBattleCreature] = [mine]
	screen.incoming_player = party
	screen.incoming_foe = [wild] as Array[VltBattleCreature]
	screen.bag = {"best_ball": 1}
	screen.incoming_decider = certain
	add_child(screen)
	screen.skip(true)

	await screen.throw_ball("best_ball")

	assert_int(party.size()).override_failure_message(
		"the creature was caught and went nowhere"
	).is_equal(2)
