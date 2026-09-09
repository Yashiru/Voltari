class_name VltExperience
extends RefCounted

## What defeating a creature is worth (spec 10, section 4).
##
## Voltari's own formula, not Gen 4's. Progression has no oracle (spec 02), so
## there is nothing here to reproduce and nothing to diverge from — this is
## design, and the exponent below is the lever it is tuned with.
##
##     XP = (a × b × L) / (5 × s) × ((2L + 10)^2.5 / (L + Lp + 10)^2.5) + 1
##
##     a   1 for a wild creature, 1.5 for a trainer's
##     b   the defeated species' base yield
##     L   the defeated creature's level
##     Lp  the earning creature's level
##     s   how many creatures share the award
##
## The ratio does the design work: beating something above your level pays
## sharply more, beating something below collapses. That is what makes grinding
## on weak targets unrewarding without a rule saying so.

## Trainers are worth half again as much.
const WILD_MULTIPLIER: float = 1.0
const TRAINER_MULTIPLIER: float = 1.5

const SHARE_DIVISOR: float = 5.0

## The authored range for a species' base yield. Wide on purpose: it is a design
## lever, and the check is here to catch a stray zero or an extra digit, not to
## express taste. Intended bands are roughly 40-70 unevolved, 150-250 fully
## evolved, 300+ for something meant to feel like an event.
const MIN_BASE_YIELD: int = 1
const MAX_BASE_YIELD: int = 1000


## Floating point is used here, and deliberately.
##
## Spec 08 bans it from the damage pipeline because that pipeline must agree with
## an oracle bit for bit. This one answers to nobody, and the exponent is
## irrational, so integers cannot express it at all.
##
## What still matters is that two machines agree. IEEE-754 requires `sqrt` to be
## correctly rounded and does NOT require it of `pow`, so `x^2.5` is written as
## x² × √x: the same value, by an operation the standard pins down.
static func award(
	base_yield: int,
	defeated_level: int,
	earner_level: int,
	sharers: int,
	from_trainer: bool,
	modifiers: Array[float] = []
) -> int:
	assert(
		base_yield >= MIN_BASE_YIELD and base_yield <= MAX_BASE_YIELD,
		"base yield %d is outside the authored range" % base_yield
	)
	assert(defeated_level >= 1 and earner_level >= 1, "levels start at 1")
	assert(sharers >= 1, "an award needs at least one earner")

	var trainer: float = TRAINER_MULTIPLIER if from_trainer else WILD_MULTIPLIER
	var share: float = (
		(trainer * float(base_yield) * float(defeated_level))
		/ (SHARE_DIVISOR * float(sharers))
	)
	var ratio: float = (
		_to_the_two_and_a_half(2 * defeated_level + 10)
		/ _to_the_two_and_a_half(defeated_level + earner_level + 10)
	)

	var total: float = share * ratio

	# Every modifier composes before the result is made whole. Applying them one
	# after another to an integer would round at each step and change the answer,
	# which is the reasoning VltDamageModifiers already follows for damage.
	for modifier: float in modifiers:
		total *= modifier

	# The +1 lands before the truncation, so an award can never be nothing —
	# and there is exactly one rounding in the whole calculation.
	return floori(total + 1.0)


static func _to_the_two_and_a_half(value: int) -> float:
	var as_float: float = float(value)
	return as_float * as_float * sqrt(as_float)
