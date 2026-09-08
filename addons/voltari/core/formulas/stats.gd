class_name VltStats
extends RefCounted

## Stat derivation from base stats, IVs, EVs, level and nature.
##
## Extracted from the oracle, not recalled. Two details would be wrong if they
## had been: the oracle's truncation is an unsigned 32-bit wrap rather than a
## plain floor, and the nature step narrows to 16 bits before dividing.
##
## Verified against tests/fixtures/oracle/procedure/stats/derivation.json.

enum Stat {
	HP,
	ATK,
	DEF,
	SPA,
	SPD,
	SPE,
}

const STAT_COUNT: int = 6

## No stat raised, or none lowered.
const NO_STAT: int = -1

const NATURE_RAISED_PERCENT: int = 110
const NATURE_LOWERED_PERCENT: int = 90

const MASK_32: int = 0xFFFFFFFF
const MASK_16: int = 0xFFFF


## The oracle truncates by unsigned wrap, not by flooring. Values in range are
## unaffected, but reproducing the operation keeps the boundary behaviour honest
## instead of merely unlikely.
static func truncate(value: int) -> int:
	assert(value >= 0, "truncate() assumes non-negative values")
	return value & MASK_32


static func truncate_16(value: int) -> int:
	assert(value >= 0, "truncate_16() assumes non-negative values")
	return value & MASK_16


## HP uses a different constant and never takes a nature modifier.
static func derive_hp(base: int, iv: int, ev: int, level: int) -> int:
	var pool: int = truncate(2 * base + iv + truncate(ev / 4) + 100)
	return truncate(pool * level / 100) + 10


## Every stat other than HP. `raised` and `lowered` name the nature's stats, or
## NO_STAT. A nature that raises and lowers the same stat is neutral by
## construction: the two adjustments are mutually exclusive branches.
static func derive_other(stat: Stat, base: int, iv: int, ev: int, level: int, raised: int, lowered: int) -> int:
	var pool: int = truncate(2 * base + iv + truncate(ev / 4))
	var value: int = truncate(pool * level / 100) + 5

	if raised == stat and lowered != stat:
		value = truncate(truncate_16(value * NATURE_RAISED_PERCENT) / 100)
	elif lowered == stat and raised != stat:
		value = truncate(truncate_16(value * NATURE_LOWERED_PERCENT) / 100)

	return value


static func derive(stat: Stat, base: int, iv: int, ev: int, level: int, raised: int, lowered: int) -> int:
	if stat == Stat.HP:
		return derive_hp(base, iv, ev, level)
	return derive_other(stat, base, iv, ev, level, raised, lowered)


## The whole spread at once, indexed by Stat.
static func derive_spread(input: VltStatInput) -> PackedInt32Array:
	var spread: PackedInt32Array = PackedInt32Array()
	spread.resize(STAT_COUNT)

	for stat: int in range(STAT_COUNT):
		spread[stat] = derive(
			stat as Stat,
			input.base[stat],
			input.ivs[stat],
			input.evs[stat],
			input.level,
			input.nature_raised,
			input.nature_lowered,
		)

	return spread
