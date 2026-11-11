{%- set dni_wstecz = 3 -%}

{{ config(materialized='incremental') }}
{{ config(incremental_strategy='insert_overwrite') }}
{{ config(partition_by={"field": "data_zdarzenia", "data_type": "date", "granularity": "day"}) }}

WITH zrodlo AS (
	SELECT
		PARSE_DATE('%Y%m%d', event_date) AS data_zdarzenia,
		TIMESTAMP_MICROS(event_timestamp) AS czas_zdarzenia,
		user_pseudo_id AS id_uzytkownika,
		event_name AS nazwa_zdarzenia,
		event_params AS parametry,
		ecommerce.purchase_revenue AS przychod,
		NULLIF(NULLIF(ecommerce.transaction_id, '(not set)'), '') AS id_transakcji

	FROM {{ source('ga4', 'zdarzenia') }}
	WHERE user_pseudo_id IS NOT NULL
	{%- if not flags.EMPTY %}
		AND REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')
		{%- if is_incremental() %}
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', COALESCE(
			DATE_SUB(_dbt_max_partition, INTERVAL {{ dni_wstecz }} DAY), DATE '{{ var("ga4_data_startu") }}'))
		{%- else %}
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE '{{ var("ga4_data_startu") }}')
		{%- endif %}
	{%- endif %}
),

testy_zdarzen AS (
	SELECT
		data_zdarzenia,
		czas_zdarzenia,
		id_uzytkownika,
		nazwa_zdarzenia,
		przychod,
		id_transakcji,
		IF(
			nazwa_zdarzenia = 'ab_assign',
			ARRAY(
				SELECT AS STRUCT
					(SELECT value.string_value FROM UNNEST(parametry) WHERE key = 'ab_test') AS slot,
					(SELECT value.string_value FROM UNNEST(parametry) WHERE key = 'ab_variant') AS wariant
			),
			ARRAY(
				SELECT AS STRUCT
					key AS slot,
					value.string_value AS wariant
				FROM UNNEST(parametry)
				WHERE REGEXP_CONTAINS(key, r'^ab\d+$')
					AND value.string_value IS NOT NULL
					AND value.string_value != 'out'
			)
		) AS testy

	FROM zrodlo
)

SELECT
	e.data_zdarzenia,
	e.czas_zdarzenia,
	e.id_uzytkownika,
	e.nazwa_zdarzenia,
	e.przychod,
	e.id_transakcji,
	t.slot,
	t.wariant

FROM testy_zdarzen AS e
LEFT JOIN UNNEST(e.testy) AS t
WHERE t.wariant IS NOT NULL
	OR e.nazwa_zdarzenia IN (SELECT zdarzenie_konwersji FROM {{ ref('stg_seeds__rejestr_testow') }})
