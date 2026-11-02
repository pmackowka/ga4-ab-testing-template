-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
{#
	Brak dziennej tabeli eksportu (przerwa, limit) zaniża wynik po cichu. Sprawdza każdy dzień
	każdego testu do dziś minus 3 dni — późniejsze dni GA4 jeszcze dopisuje. Wiersz = brakujący dzień.
	Czyta tylko pseudokolumnę _TABLE_SUFFIX, bez kolumn z danymi, więc kosztuje minimum stawki.
#}
WITH tests AS (
	SELECT
		test_id,
		test_start,
		LEAST(test_end, DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)) AS checked_end

	FROM {{ ref('stg_seeds__ab_tests') }}
),

export_days AS (
	SELECT DISTINCT PARSE_DATE('%Y%m%d', _TABLE_SUFFIX) AS export_day

	FROM {{ source('ga4', 'events') }}
	WHERE REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE '{{ var("ga4_start_date") }}')
)

SELECT
	t.test_id,
	day AS missing_day

FROM tests AS t
-- test, który jeszcze nie ma dnia starszego niż 3 dni, daje pustą tablicę i nic nie sprawdza
CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(t.test_start, t.checked_end)) AS day
LEFT JOIN export_days AS d
	ON d.export_day = day
WHERE d.export_day IS NULL
