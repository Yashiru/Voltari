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
