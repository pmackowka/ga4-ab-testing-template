-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
-- Reguły z ASSERT-ów sql/03 dla każdego wiersza seeds/rejestr_testow.csv. Wiersz wyniku = błąd konfiguracji.
WITH testy AS (
	SELECT
		*,
		-- poprzedni test w tym samym slocie: jego okno musi się skończyć przed startem tego
		-- funkcja okna: LAG bierze wartość z poprzedniego wiersza w obrębie PARTITION BY (ten sam slot),
		-- w kolejności ORDER BY; pierwszy test w slocie dostaje NULL, a porównania z NULL nie zgłaszają błędu
		LAG(koniec_testu) OVER (PARTITION BY slot ORDER BY start_testu) AS poprzedni_koniec_w_slocie

	FROM {{ ref('stg_seeds__rejestr_testow') }}
)

SELECT
	id_testu,
	powod

-- wzorzec „lista reguł”: każda reguła to IF(błąd, 'opis', NULL), [ … ] składa je w tablicę,
-- przecinek przed UNNEST to CROSS JOIN z tablicą z tego samego wiersza → jeden wiersz na regułę,
-- WHERE powod IS NOT NULL zostawia tylko złamane. Jeden test, wiele komunikatów
FROM testy,
	UNNEST([
		IF(NOT REGEXP_CONTAINS(slot, r'^ab\d+$'),
			'slot musi być slotem abN — staging czyta tylko parametry ^ab\\d+$', NULL),
		-- DAYOFWEEK w BigQuery: 1 = niedziela, 2 = poniedziałek … 7 = sobota
		IF(EXTRACT(DAYOFWEEK FROM start_testu) != 2, 'start_testu musi być poniedziałkiem', NULL),
		IF(EXTRACT(DAYOFWEEK FROM koniec_testu) != 1 OR koniec_testu <= start_testu,
			'koniec_testu musi być niedzielą po start_testu: pełne tygodnie', NULL),
		IF(wariant_kontrolny NOT IN UNNEST(warianty), 'wariant_kontrolny musi być na liście warianty', NULL),
		IF(ARRAY_LENGTH(warianty) < 2, 'warianty musi mieć co najmniej dwa warianty', NULL),
		-- pusta komórka daje NULL, a IN UNNEST(NULL) nigdy nie jest prawdą: zero ekspozycji bez błędu
		IF(IFNULL(ARRAY_LENGTH(zdarzenia_ekspozycji), 0) = 0, 'zdarzenia_ekspozycji nie może być puste', NULL),
		IF(start_testu < DATE '{{ var("ga4_data_startu") }}',
			'start_testu przed ga4_data_startu: staging nie ma tych dni', NULL),
			{# po kompilacji: start_testu < DATE '2026-08-24' — np. test ze startem 2026-08-17 łamie regułę #}
		-- nakładające się okna w jednym slocie: event z parametrem slotu pasowałby do dwóch testów
		IF(start_testu <= poprzedni_koniec_w_slocie,
			'okno nakłada się na poprzedni test w tym slocie', NULL),
		-- ciasteczko trzyma sam wariant i żyje DAYS = 60 dni od losowania (gtm/), a ostatnie losowanie
		-- bywa w dniu końca testu; wcześniejszy start przeniósłby stary podział do nowego testu
		-- przykład: poprzedni ab2 kończy się 2026-10-04 → start 2026-11-30 (57 dni) łamie regułę,
		-- start 2026-12-07 (64 dni) przechodzi
		IF(start_testu > poprzedni_koniec_w_slocie
			AND DATE_DIFF(start_testu, poprzedni_koniec_w_slocie, DAY) <= 60,
			'slot wraca przed wygaśnięciem ciasteczek poprzedniego testu: start musi być > 60 dni po jego końcu', NULL)
	]) AS powod
WHERE powod IS NOT NULL
