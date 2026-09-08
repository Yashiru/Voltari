class_name VltFuzzDecider
extends VltSeededDecider

## A seeded decider that also exposes a general-purpose draw, for scaffolding
## that has to GENERATE battles rather than resolve them.
##
## It lives outside the core deliberately. Every random decision the engine
## makes must be enumerable by reading VltDecider, and a general draw would be a
## hole in that guarantee — so the core cannot reach this, and the purity lint
## refuses `next_in_range` under core/ to keep it that way.


func next_in_range(minimum: int, maximum: int) -> int:
	assert(minimum <= maximum, "range is inverted")
	return minimum + _below(maximum - minimum + 1)


func chance(percent: int) -> bool:
	return next_in_range(1, 100) <= percent


func pick(options: Array) -> Variant:
	assert(not options.is_empty(), "nothing to pick from")
	return options[next_in_range(0, options.size() - 1)]


## Typed variants, so callers never have to narrow a Variant themselves.
func pick_int(options: Array[int]) -> int:
	assert(not options.is_empty(), "nothing to pick from")
	return options[next_in_range(0, options.size() - 1)]


func pick_string(options: Array[String]) -> String:
	assert(not options.is_empty(), "nothing to pick from")
	return options[next_in_range(0, options.size() - 1)]
