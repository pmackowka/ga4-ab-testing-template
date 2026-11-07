{#
	Staging: eventy GA4 z wariantem dowolnego testu (parametr slotu ab1…ab10 albo ab_assign)
	i eventy konwersji z seeda. Wiersz = event × slot.
	Przyrost: nadpisuje ostatnie dni_wstecz dni od najnowszej partycji (_dbt_max_partition), nie od
	CURRENT_DATE(), żeby przerwa w harmonogramie nie zostawiła dziury. Zmiana logiki = --full-refresh.
	Target sandbox: zwykła tabela bez partycji, odtwarzana w całości (sandbox nie ma MERGE).
#}
{%- set dni_wstecz = 3 -%}

{%- set sandbox = target.name == 'sandbox' -%}

{{ config(materialized='table' if sandbox else 'incremental') }}
{{ config(incremental_strategy='insert_overwrite') }}
{{ config(partition_by=none if sandbox else {"field": "data_zdarzenia", "data_type": "date", "granularity": "day"}) }}

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

{#
	Przykładowy wynik (dane syntetyczne); dwa ostatnie wiersze to jeden event z dwoma slotami:
	data_zdarzenia | czas_zdarzenia      | id_uzytkownika | nazwa_zdarzenia | przychod | id_transakcji | slot | wariant
	2026-09-08     | 2026-09-08 10:00:00 | 1234.5678      | ab_assign       | NULL     | NULL          | ab2  | v1
	2026-09-08     | 2026-09-08 10:02:13 | 1234.5678      | view_item       | NULL     | NULL          | ab2  | v1
	2026-09-12     | 2026-09-12 18:30:00 | 9999.0009      | purchase        | 249.90   | T-100231      | NULL | NULL
	2026-11-03     | 2026-11-03 09:15:40 | 4444.0003      | view_item       | NULL     | NULL          | ab4  | v0
	2026-11-03     | 2026-11-03 09:15:40 | 4444.0003      | view_item       | NULL     | NULL          | ab5  | v1
#}
