-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
-- Reguły z ASSERT-ów sql/03 dla każdego wiersza seeds/ab_tests.csv. Wiersz wyniku = błąd konfiguracji.
WITH tests AS (
	SELECT
		*,
		-- poprzedni test w tym samym slocie: jego okno musi się skończyć przed startem tego
		LAG(test_end) OVER (PARTITION BY test_name ORDER BY test_start) AS prev_test_end_in_slot

	FROM {{ ref('stg_seeds__ab_tests') }}
)

SELECT
	test_id,
	reason

FROM tests,
	UNNEST([
		IF(NOT REGEXP_CONTAINS(test_name, r'^ab\d+$'),
			'test_name musi być slotem abN — staging czyta tylko parametry ^ab\\d+$', NULL),
		IF(EXTRACT(DAYOFWEEK FROM test_start) != 2, 'test_start musi być poniedziałkiem', NULL),
		IF(EXTRACT(DAYOFWEEK FROM test_end) != 1 OR test_end <= test_start,
			'test_end musi być niedzielą po test_start: pełne tygodnie', NULL),
		IF(control_variant NOT IN UNNEST(variants), 'control_variant musi być na liście variants', NULL),
		IF(ARRAY_LENGTH(variants) < 2, 'variants musi mieć co najmniej dwa warianty', NULL),
		IF(test_start < DATE '{{ var("ga4_start_date") }}',
			'test_start przed ga4_start_date: staging nie ma tych dni', NULL),
		-- nakładające się okna w jednym slocie: event z parametrem slotu pasowałby do dwóch testów
		IF(test_start <= prev_test_end_in_slot,
			'okno nakłada się na poprzedni test w tym slocie', NULL)
	]) AS reason
WHERE reason IS NOT NULL
