-- Rejestr testów z listami jako ARRAY — modele niżej używają IN UNNEST zamiast parsować tekst.
SELECT
	test_name,
	test_start,
	test_end,
	control_variant,
	SPLIT(variants, '|') AS variants,
	conversion_event,
	SPLIT(exposure_events, '|') AS exposure_events,
	DATE_DIFF(test_end, test_start, DAY) + 1 AS test_days,
	-- GA4 dopisuje dane do 72 h: wcześniej wynik zaniża ostatnie dni (ASSERT w sql/03)
	test_end <= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY) AS is_final

FROM {{ ref('ab_tests') }}
