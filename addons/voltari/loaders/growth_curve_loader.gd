class_name VltGrowthCurveLoader
extends RefCounted

## Turns the built curve payload into the tables progression reads.
##
## A curve is the cumulative experience needed to REACH each level, indexed from
## zero: entry 0 is level 1 and is always zero. Stored as a table rather than a
## formula because the tables are what was verified — two of the six curves are
## piecewise and have no closed form to check against (spec 10, section 9).

## Curve id to totals, one entry per level.
@warning_ignore_start("unsafe_cast")
static func from_payload(payload: Dictionary) -> Dictionary[String, PackedInt32Array]:
	var curves: Dictionary[String, PackedInt32Array] = {}

	for entry: Variant in (payload["curves"] as Dictionary).keys():
		var name: String = entry as String
		var totals: PackedInt32Array = PackedInt32Array()

		for total: Variant in (payload["curves"] as Dictionary)[name] as Array:
			totals.append(int(total as float))

		assert(not totals.is_empty(), "growth curve \"%s\" is empty" % name)
		assert(totals[0] == 0, "growth curve \"%s\" does not start at zero" % name)
		curves[name] = totals

	return curves
@warning_ignore_restore("unsafe_cast")
