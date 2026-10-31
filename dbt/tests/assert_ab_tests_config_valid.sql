-- Reguły z ASSERT-ów sql/03 dla każdego wiersza seeds/ab_tests.csv. Wiersz wyniku = błąd konfiguracji.
SELECT
	test_name,
	reason

FROM {{ ref('stg_seeds__ab_tests') }},
	UNNEST([
		IF(EXTRACT(DAYOFWEEK FROM test_start) != 2, 'test_start musi być poniedziałkiem', NULL),
		IF(EXTRACT(DAYOFWEEK FROM test_end) != 1 OR test_end <= test_start,
			'test_end musi być niedzielą po test_start: pełne tygodnie', NULL),
		IF(control_variant NOT IN UNNEST(variants), 'control_variant musi być na liście variants', NULL),
		IF(ARRAY_LENGTH(variants) < 2, 'variants musi mieć co najmniej dwa warianty', NULL),
		IF(test_start < DATE '{{ var("ga4_start_date") }}',
			'test_start przed ga4_start_date: staging nie ma tych dni', NULL)
	]) AS reason
WHERE reason IS NOT NULL
