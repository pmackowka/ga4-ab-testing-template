{#
	Staging: eventy GA4 potrzebne do testów A/B — wszystkie z parametrem ab_test i eventy konwersji
	z seeds/ab_tests.csv. Reszta ruchu nie trafia do tabeli, więc jest mała mimo dużego eksportu.

	insert_overwrite, nie merge: eksport GA4 nie ma klucza eventu, a jednostką poprawki jest dzień —
	GA4 dopisuje do dziennej tabeli jeszcze do 72 h. Każdy przebieg nadpisuje w całości ostatnie
	dni (lookback_days) od najnowszej partycji w tabeli, więc spóźnione eventy wchodzą bez duplikatów.
	Liczone od _dbt_max_partition (zmienna, którą dbt deklaruje w skrypcie insert_overwrite), a nie od
	CURRENT_DATE(), żeby kilkudniowa przerwa w harmonogramie nie zostawiła dziury w danych.

	hours_to_expiration=none — nadpisuje 1 h z dbt_project.yml; inaczej w dev tabela znika przed
	kolejnym przebiegiem i ścieżka incremental nigdy się nie wykonuje.
#}
{%- set lookback_days = 3 -%}

{{
	config(
		materialized='incremental',
		incremental_strategy='insert_overwrite',
		hours_to_expiration=none,
		on_schema_change='append_new_columns',
		partition_by={
			"field": "event_date",
			"data_type": "date",
			"granularity": "day"
		}
	)
}}

WITH source AS (
	SELECT
		PARSE_DATE('%Y%m%d', _TABLE_SUFFIX) AS event_date,
		TIMESTAMP_MICROS(event_timestamp) AS event_ts,
		user_pseudo_id,
		event_name,
		(SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test') AS ab_test,
		(SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_variant') AS ab_variant

	FROM {{ source('ga4', 'events') }}
	-- filtry na _TABLE_SUFFIX ze stałymi ograniczają, które tabele dzienne BigQuery w ogóle czyta
	WHERE REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')
	{% if is_incremental() %}
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(_dbt_max_partition, INTERVAL {{ lookback_days }} DAY))
	{% else %}
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE '{{ var("ga4_start_date") }}')
	{% endif %}
		-- Consent Mode bez zgody na analytics_storage wysyła eventy bez user_pseudo_id; bez filtra
		-- wszyscy tacy użytkownicy zlewają się w jednego z wariantem i zakupami wielu osób
		AND user_pseudo_id IS NOT NULL
)

SELECT *

FROM source
WHERE ab_test IS NOT NULL
	OR event_name IN (SELECT conversion_event FROM {{ ref('stg_seeds__ab_tests') }})
