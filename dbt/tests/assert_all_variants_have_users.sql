-- Wariant z seeda bez użytkowników, gdy inne warianty tego testu je mają: tag nie losuje tego
-- wariantu albo zmienna GTM go odrzuca. sql/03 przerywa się wtedy błędem „brakuje wariantu”.
SELECT
	test_id,
	variant

FROM {{ ref('fct_ab_test_results') }}
WHERE users = 0
	AND test_id IN (SELECT test_id FROM {{ ref('fct_ab_test_results') }} WHERE users > 0)
