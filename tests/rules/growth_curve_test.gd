extends GdUnitTestSuite

## The experience curves, as loaded.
##
## Progression has no oracle (spec 02), so these numbers get no differential.
## What they get is a published source recorded beside them, a seeding tool that
## checked the four closed-form curves against their own formula, and this.

const CURVES_PAYLOAD: String = "res://content/generated/growth-curves.json"
const SPECIES_DIR: String = "res://content/generated/species"
const MAX_LEVEL: int = 100

var _curves: Dictionary[String, PackedInt32Array]


func before() -> void:
	_curves = VltGrowthCurveLoader.from_payload(
		VltContentPayloads.read_json(CURVES_PAYLOAD)
	)


func test_every_curve_covers_every_level() -> void:
	assert_int(_curves.size()).is_equal(6)
	for name: String in _curves.keys():
		assert_int(_curves[name].size()).override_failure_message(
			"curve \"%s\" does not cover 100 levels" % name
		).is_equal(MAX_LEVEL)


func test_a_curve_starts_at_zero_and_only_climbs() -> void:
	# A creature at level 1 has earned nothing, and experience never goes
	# backwards — the property that makes "level from total" well defined.
	for name: String in _curves.keys():
		var totals: PackedInt32Array = _curves[name]
		assert_int(totals[0]).override_failure_message(
			"curve \"%s\" does not start at zero" % name
		).is_equal(0)

		for level: int in range(1, totals.size()):
			assert_int(totals[level]).override_failure_message(
				"curve \"%s\" does not climb at level %d" % [name, level + 1]
			).is_greater(totals[level - 1])


func test_the_curves_differ_from_one_another() -> void:
	# Six names for one table would be six ways of saying the same thing, and
	# nothing else here would notice.
	var totals_at_100: Dictionary[int, bool] = {}
	for name: String in _curves.keys():
		totals_at_100[_curves[name][MAX_LEVEL - 1]] = true

	assert_int(totals_at_100.size()).override_failure_message(
		"curves share a total at level 100, so at least two are the same table"
	).is_equal(6)


func test_the_closed_form_curves_match_their_formula() -> void:
	# Derived here, independently of the seeding tool, so this is a second
	# opinion rather than the same arithmetic agreeing with itself. Level 1 is
	# excluded: it is zero by definition and the cubics disagree — medium_slow
	# gives -54 there.
	for level: int in range(2, MAX_LEVEL + 1):
		var cube: int = level * level * level
		assert_int(_curves["medium_fast"][level - 1]).is_equal(cube)
		assert_int(_curves["fast"][level - 1]).is_equal(floori(4.0 * cube / 5.0))
		assert_int(_curves["slow"][level - 1]).is_equal(floori(5.0 * cube / 4.0))
		assert_int(_curves["medium_slow"][level - 1]).is_equal(
			floori(1.2 * cube - 15.0 * level * level + 100.0 * level - 140.0)
		)


func test_every_species_names_a_curve_that_exists() -> void:
	# The build checks this too, but in its own terms. This is the engine's:
	# a species whose curve is missing would level nowhere at all.
	var species: Dictionary[String, VltSpecies] = VltSpeciesLoader.from_entries(
		VltContentPayloads.read_indexed(SPECIES_DIR)
	)

	for id: String in species.keys():
		assert_bool(_curves.has(species[id].growth_rate)).override_failure_message(
			"species \"%s\" names curve \"%s\", which no table declares"
			% [id, species[id].growth_rate]
		).is_true()
