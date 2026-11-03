-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
-- Wariant z seeda bez użytkowników, gdy inne warianty tego testu je mają: tag nie losuje tego
-- wariantu albo zmienna GTM go odrzuca. sql/03 przerywa się wtedy błędem „brakuje wariantu”.
SELECT
	test_id,
	variant

FROM {{ ref('fct_ab_test_results') }}
WHERE users = 0
	AND test_id IN (SELECT test_id FROM {{ ref('fct_ab_test_results') }} WHERE users > 0)
