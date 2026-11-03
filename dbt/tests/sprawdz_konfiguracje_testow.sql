-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
-- Reguły z ASSERT-ów sql/03 dla każdego wiersza seeds/rejestr_testow.csv. Wiersz wyniku = błąd konfiguracji.
WITH testy AS (
	SELECT
		*,
		-- poprzedni test w tym samym slocie: jego okno musi się skończyć przed startem tego
		LAG(koniec_testu) OVER (PARTITION BY slot ORDER BY start_testu) AS poprzedni_koniec_w_slocie

	FROM {{ ref('stg_seeds__rejestr_testow') }}
)

SELECT
	id_testu,
	powod

FROM testy,
	UNNEST([
		IF(NOT REGEXP_CONTAINS(slot, r'^ab\d+$'),
			'slot musi być slotem abN — staging czyta tylko parametry ^ab\\d+$', NULL),
		IF(EXTRACT(DAYOFWEEK FROM start_testu) != 2, 'start_testu musi być poniedziałkiem', NULL),
		IF(EXTRACT(DAYOFWEEK FROM koniec_testu) != 1 OR koniec_testu <= start_testu,
			'koniec_testu musi być niedzielą po start_testu: pełne tygodnie', NULL),
		IF(wariant_kontrolny NOT IN UNNEST(warianty), 'wariant_kontrolny musi być na liście warianty', NULL),
		IF(ARRAY_LENGTH(warianty) < 2, 'warianty musi mieć co najmniej dwa warianty', NULL),
		IF(start_testu < DATE '{{ var("ga4_data_startu") }}',
			'start_testu przed ga4_data_startu: staging nie ma tych dni', NULL),
		-- nakładające się okna w jednym slocie: event z parametrem slotu pasowałby do dwóch testów
		IF(start_testu <= poprzedni_koniec_w_slocie,
			'okno nakłada się na poprzedni test w tym slocie', NULL)
	]) AS powod
WHERE powod IS NOT NULL
