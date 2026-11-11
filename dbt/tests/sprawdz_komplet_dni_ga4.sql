WITH testy AS (
	SELECT
		id_testu,
		start_testu,
		LEAST(koniec_testu, DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)) AS koniec_sprawdzania

	FROM {{ ref('stg_seeds__rejestr_testow') }}
),

dni_eksportu AS (
	SELECT DISTINCT PARSE_DATE('%Y%m%d', _TABLE_SUFFIX) AS dzien_eksportu

	FROM {{ source('ga4', 'zdarzenia') }}
	WHERE REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE '{{ var("ga4_data_startu") }}')
)

SELECT
	t.id_testu,
	dzien AS brakujacy_dzien

FROM testy AS t
CROSS JOIN UNNEST(GENERATE_DATE_ARRAY(t.start_testu, t.koniec_sprawdzania)) AS dzien
LEFT JOIN dni_eksportu AS d
	ON d.dzien_eksportu = dzien
WHERE d.dzien_eksportu IS NULL
