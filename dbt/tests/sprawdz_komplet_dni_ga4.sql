-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
{#
	Brak dziennej tabeli eksportu (przerwa, limit) zaniża wynik po cichu. Sprawdza każdy dzień
	każdego testu do dziś minus 3 dni — późniejsze dni GA4 jeszcze dopisuje. Wiersz = brakujący dzień.
	Czyta tylko pseudokolumnę _TABLE_SUFFIX, bez kolumn z danymi, więc kosztuje minimum stawki.
#}
WITH testy AS (
	SELECT
		id_testu,
		start_testu,
		-- LEAST = mniejsza z wartości: test trwający sprawdzamy tylko do dziś minus 3 dni
		LEAST(koniec_testu, DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)) AS koniec_sprawdzania

	FROM {{ ref('stg_seeds__rejestr_testow') }}
),

dni_eksportu AS (
	SELECT DISTINCT PARSE_DATE('%Y%m%d', _TABLE_SUFFIX) AS dzien_eksportu

	FROM {{ source('ga4', 'zdarzenia') }}
	WHERE REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE '{{ var("ga4_data_startu") }}')
			{# po kompilacji: DATE '2026-08-24' → _TABLE_SUFFIX >= '20260824' #}
)

SELECT
	t.id_testu,
	dzien AS brakujacy_dzien

FROM testy AS t
-- test, który jeszcze nie ma dnia starszego niż 3 dni, daje pustą tablicę i nic nie sprawdza
-- GENERATE_DATE_ARRAY(od, do) = tablica wszystkich dni od–do włącznie; UNNEST robi z niej wiersze
CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(t.start_testu, t.koniec_sprawdzania)) AS dzien
	-- przykład: ab4 start 2026-11-02, dziś 2026-11-06 → koniec_sprawdzania 2026-11-03
	-- → [2026-11-02, 2026-11-03] → 2 wiersze; brak events_20261103 = 1 wiersz błędu
-- anti-join: LEFT JOIN + WHERE prawa strona IS NULL = dni, dla których nie ma tabeli eksportu
LEFT JOIN dni_eksportu AS d
	ON d.dzien_eksportu = dzien
WHERE d.dzien_eksportu IS NULL
