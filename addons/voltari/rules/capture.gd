class_name VltCapture
extends RefCounted

## Stages one and two of the capture formula (spec 11, section 2).
##
## L1: same purity as the core. It reads the ball, the species and the target's
## condition, and produces a single number. The third stage — four checks against
## that number — is the core's, because by then no content is needed.
##
##     a = floor( ((3·HPmax − 2·HPcur) × rate × ballBonus) / (3·HPmax) × statusBonus )
##     b = 1048560 / sqrt(sqrt(16711680 / a))
##
## **The four checks are tension, not balance.** Since 16711680 is 255 × 65536 and
## 1048560 ÷ 16 is 65535, `b` is 65535 × (a/255)^(1/4) — a quarter power, so four
## independent checks give back a/255, the raw ratio. Stage two decides how many
## shakes are seen before a failure, never how often capture succeeds
## (decision 0033).

## `a` is capped here, and reaching the cap means certain capture.
const MAX_RATE: int = 255

## What stage two would return for a certain capture. A draw runs 0 to 65535, so
## every check passes — the core keeps one path instead of a special case.
const CERTAIN_THRESHOLD: int = 65536

## Constants of the published stage-two form, named rather than left as digits:
## 255 × 65536, and 16 × 65535.
const RATE_SCALE: int = 16711680
const THRESHOLD_SCALE: int = 1048560


## Stage one. One floor, at the end, exactly where the formula puts it.
##
## The two design levers both live here. The health fraction is 1/3 at full
## health and approaches 1 at a single point, so weakening a target very nearly
## triples the odds; the status bonus rewards inflicting one. Everything that
## balances capture acts on this number.
static func modified_rate(
	max_hp: int,
	current_hp: int,
	species_rate: int,
	ball_multiplier: float,
	status_multiplier: float
) -> int:
	assert(max_hp > 0, "a creature with no maximum health cannot be caught")
	assert(current_hp >= 0 and current_hp <= max_hp, "current health is outside the creature")
	assert(species_rate >= 0, "a capture rate cannot be negative")
	assert(ball_multiplier > 0.0 and status_multiplier > 0.0, "multipliers scale, they do not zero")

	var health: float = float(3 * max_hp - 2 * current_hp) / float(3 * max_hp)
	var rate: float = health * float(species_rate) * ball_multiplier * status_multiplier

	return mini(floori(rate), MAX_RATE)


## Stage two, integer throughout: every division and every root floors, in the
## order the formula writes them.
##
## Returns CERTAIN_THRESHOLD when the rate reached its cap. That is the one place
## the formula branches, and it is here rather than in the core so the core has
## nothing to know about it.
static func shake_threshold(rate: int) -> int:
	assert(rate >= 0 and rate <= MAX_RATE, "a modified rate of %d is out of range" % rate)

	if rate >= MAX_RATE:
		return CERTAIN_THRESHOLD
	if rate == 0:
		return 0

	var inner: int = RATE_SCALE / rate
	return THRESHOLD_SCALE / _floor_sqrt(_floor_sqrt(inner))


## Integer square root, floored — no float ever enters stage two.
##
## Newton's method rather than `sqrt()`: the values reach sixteen million, and a
## float root there is correctly rounded but still a float, so flooring it would
## depend on the last bit. This depends on nothing.
static func _floor_sqrt(value: int) -> int:
	if value < 2:
		return value

	var guess: int = value
	var next: int = (guess + 1) / 2

	while next < guess:
		guess = next
		next = (guess + value / guess) / 2

	return guess
