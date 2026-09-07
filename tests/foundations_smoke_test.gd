# Smoke test: proves the CI test pipeline actually executes GDScript.
# Delete once the first real core test suite lands.
extends GdUnitTestSuite


func test_test_pipeline_executes() -> void:
	var value: int = 1 + 1
	assert_int(value).is_equal(2)
