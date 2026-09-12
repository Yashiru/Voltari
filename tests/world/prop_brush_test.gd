extends GdUnitTestSuite

## What the next prop will look like when it lands.
##
## The half of the brush that carries numbers, and therefore the half worth
## asserting: a scatter that never varies and a scatter that occasionally
## produces a prop scaled to nothing both look fine until somebody happens to
## look at the wrong prop.

const SMALLEST: float = VltPropBrush.SMALLEST

## Enough draws that a range is actually explored rather than sampled once.
const MANY: int = 400


# --- no variation at all ------------------------------------------------------


func test_with_no_spread_every_prop_is_identical() -> void:
	# The default, and the case an author is in while placing one deliberate
	# thing. A draw from an empty range is not contractually the same number
	# every time, so this is stated rather than assumed.
	var brush: VltPropBrush = _brush()
	brush.turn = 30.0
	brush.size = 1.5

	var first: Transform3D = brush.next_at(Vector3.ZERO)
	for repeat: int in range(MANY):
		brush.placed()
		assert_bool(brush.next_at(Vector3.ZERO).is_equal_approx(first)).is_true()


func test_a_prop_stands_on_the_point_it_was_given() -> void:
	# A model is authored standing on its own origin, so the origin on the ground
	# is what makes a prop stand on it rather than sink into it.
	var brush: VltPropBrush = _brush()
	brush.turn_spread = 180.0
	brush.size_spread = 0.5

	for repeat: int in range(MANY):
		brush.placed()
		var where: Vector3 = Vector3(3.0, 1.25, -7.0)
		assert_bool(brush.next_at(where).origin.is_equal_approx(where)).is_true()


# --- the turn -----------------------------------------------------------------


func test_a_prop_is_never_tilted() -> void:
	# Decision 0075: the brush turns about the vertical only. The footprint maths
	# would cope with a tilt, but everything a prop is placed on is the ground and
	# a tilted fence post is a mistake far more often than a decision.
	var brush: VltPropBrush = _brush()
	brush.turn_spread = 180.0
	brush.size_spread = 0.4

	for repeat: int in range(MANY):
		brush.placed()
		var basis: Basis = brush.next_at(Vector3.ZERO).basis
		# Upright means the vertical column is vertical, and nothing else leans
		# into it.
		assert_float(basis.y.normalized().dot(Vector3.UP)).is_equal_approx(1.0, 0.0001)
		assert_float(basis.x.y).is_equal_approx(0.0, 0.0001)
		assert_float(basis.z.y).is_equal_approx(0.0, 0.0001)


func test_a_turn_spread_stays_inside_what_was_asked_for() -> void:
	var brush: VltPropBrush = _brush()
	brush.turn = 90.0
	brush.turn_spread = 15.0

	for repeat: int in range(MANY):
		brush.placed()
		var degrees: float = rad_to_deg(_angle_of(brush.next_at(Vector3.ZERO)))
		assert_float(degrees).is_between(90.0 - 15.0 - 0.001, 90.0 + 15.0 + 0.001)


func test_a_turn_spread_actually_varies() -> void:
	# The failure that hides: a scatter that quietly places the same thing every
	# time reads as a scatter until two props are compared.
	var brush: VltPropBrush = _brush()
	brush.turn_spread = 20.0

	var seen: Dictionary[float, bool] = {}
	for repeat: int in range(MANY):
		brush.placed()
		seen[snappedf(_angle_of(brush.next_at(Vector3.ZERO)), 0.0001)] = true
	assert_int(seen.size()).is_greater(MANY / 2)


# --- the size -----------------------------------------------------------------


func test_a_size_spread_stays_inside_what_was_asked_for() -> void:
	var brush: VltPropBrush = _brush()
	brush.size = 1.0
	brush.size_spread = 0.2

	for repeat: int in range(MANY):
		brush.placed()
		assert_float(_size_of(brush.next_at(Vector3.ZERO))).is_between(0.8 - 0.001, 1.2 + 0.001)


func test_a_prop_is_never_scaled_to_nothing() -> void:
	# A spread wider than the size it varies is a typo, and a prop scaled to
	# nothing draws nothing, blocks nothing and cannot be clicked — invisible in
	# every sense, including to whoever is looking for what went wrong.
	var brush: VltPropBrush = _brush()
	brush.size = 0.3
	brush.size_spread = 2.0

	# Read back through a basis, so the floor comes out a hair under itself: the
	# scale goes in as a number and comes back as the length of a column, which is
	# a square root away from it. What matters is that it is the floor and not
	# something near zero.
	for repeat: int in range(MANY):
		brush.placed()
		assert_float(_size_of(brush.next_at(Vector3.ZERO))).is_greater(SMALLEST * 0.99)


func test_a_size_is_the_same_on_both_ground_axes() -> void:
	# One number, not three. A prop squashed along one axis is something somebody
	# occasionally wants and never wants by accident, which is what independent
	# spreads would hand out.
	var brush: VltPropBrush = _brush()
	brush.size_spread = 0.4

	for repeat: int in range(MANY):
		brush.placed()
		var basis: Basis = brush.next_at(Vector3.ZERO).basis
		assert_float(basis.x.length()).is_equal_approx(basis.z.length(), 0.0001)
		assert_float(basis.x.length()).is_equal_approx(basis.y.length(), 0.0001)


# --- repeatability ------------------------------------------------------------


func test_one_seed_lays_down_one_row() -> void:
	# What makes the spread testable at all, and what would let a scattered row
	# be laid down twice the same way if that is ever wanted.
	var wanted: Array[Transform3D] = _row(_brush(), 20)
	assert_int(_row(_brush(), 20).size()).is_equal(wanted.size())

	var again: Array[Transform3D] = _row(_brush(), 20)
	for index: int in range(wanted.size()):
		assert_bool(again[index].is_equal_approx(wanted[index])).is_true()


func test_another_seed_lays_down_another_row() -> void:
	var wanted: Array[Transform3D] = _row(_brush(), 20)
	var other: Array[Transform3D] = _row(VltPropBrush.new(99999), 20)

	var same: int = 0
	for index: int in range(wanted.size()):
		if other[index].is_equal_approx(wanted[index]):
			same += 1
	assert_int(same).is_less(wanted.size())


# --- fixtures -----------------------------------------------------------------


## Seeded, so every assertion above is about the arithmetic rather than about
## which numbers happened to come up.
func _brush() -> VltPropBrush:
	return VltPropBrush.new(20260912)


func _row(brush: VltPropBrush, count: int) -> Array[Transform3D]:
	brush.turn_spread = 30.0
	brush.size_spread = 0.25

	var laid: Array[Transform3D] = []
	for index: int in range(count):
		laid.append(brush.next_at(Vector3(float(index), 0.0, 0.0)))
		brush.placed()
	return laid


## The turn a transform carries, about the vertical.
static func _angle_of(at: Transform3D) -> float:
	return at.basis.get_euler().y


## The size a transform carries, on the ground plane.
static func _size_of(at: Transform3D) -> float:
	return at.basis.x.length()


# --- what the preview is allowed to promise -----------------------------------


func test_asking_twice_without_placing_answers_the_same() -> void:
	# The preview's whole contract: what is under the cursor is what will land
	# there. Redrawing per call would make it spin and pulse while promising
	# nothing.
	var brush: VltPropBrush = _brush()
	brush.turn_spread = 45.0
	brush.size_spread = 0.5

	var shown: Transform3D = brush.next_at(Vector3.ZERO)
	for repeat: int in range(20):
		assert_bool(brush.next_at(Vector3.ZERO).is_equal_approx(shown)).is_true()


func test_the_pending_prop_follows_the_cursor_without_changing() -> void:
	# Moving the mouse moves the preview and must not reroll it.
	var brush: VltPropBrush = _brush()
	brush.turn_spread = 45.0

	var here: Transform3D = brush.next_at(Vector3.ZERO)
	var there: Transform3D = brush.next_at(Vector3(7.0, 0.0, 2.0))
	assert_bool(there.basis.is_equal_approx(here.basis)).is_true()
	assert_bool(there.origin.is_equal_approx(Vector3(7.0, 0.0, 2.0))).is_true()


func test_placing_one_draws_the_next() -> void:
	var brush: VltPropBrush = _brush()
	brush.turn_spread = 45.0

	var first: Transform3D = brush.next_at(Vector3.ZERO)
	brush.placed()

	var different: bool = false
	for repeat: int in range(20):
		if not brush.next_at(Vector3.ZERO).basis.is_equal_approx(first.basis):
			different = true
			break
		brush.placed()
	assert_bool(different).is_true()


func test_changing_a_setting_redraws_what_is_pending() -> void:
	# Otherwise the preview keeps showing the old numbers until something is
	# placed — which is the one moment an author is certainly looking at it.
	var brush: VltPropBrush = _brush()
	brush.size = 1.0
	var before: Transform3D = brush.next_at(Vector3.ZERO)

	brush.size = 4.0
	brush.restyled()
	assert_float(_size_of(brush.next_at(Vector3.ZERO))).is_not_equal(_size_of(before))


func test_a_brush_with_no_model_has_nothing_to_lay_down() -> void:
	assert_bool(VltPropBrush.new().ready_to_paint()).is_false()


func test_a_brush_naming_a_model_is_ready() -> void:
	var brush: VltPropBrush = _brush()
	brush.item = 7
	assert_bool(brush.ready_to_paint()).is_true()
