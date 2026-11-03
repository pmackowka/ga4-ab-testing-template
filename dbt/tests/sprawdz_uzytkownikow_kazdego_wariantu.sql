-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
-- Wariant z seeda bez użytkowników, gdy inne warianty tego testu je mają: tag nie losuje tego
-- wariantu albo zmienna GTM go odrzuca. sql/03 przerywa się wtedy błędem „brakuje wariantu”.
SELECT
	id_testu,
	wariant

FROM {{ ref('fct_wyniki_testow_ab') }}
WHERE uzytkownicy = 0
	AND id_testu IN (SELECT id_testu FROM {{ ref('fct_wyniki_testow_ab') }} WHERE uzytkownicy > 0)
