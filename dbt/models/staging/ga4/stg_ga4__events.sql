{#
	Staging: eventy GA4 potrzebne do testów A/B — z wariantem jakiegokolwiek testu (parametr slotu
	ab1…ab10 albo ab_assign) i eventy konwersji z seeds/ab_tests.csv. Reszta ruchu nie trafia
	do tabeli, więc jest mała mimo dużego eksportu.

	insert_overwrite, nie merge: eksport GA4 nie ma klucza eventu, a jednostką poprawki jest dzień —
	GA4 dopisuje do dziennej tabeli jeszcze do 72 h. Każdy przebieg nadpisuje w całości ostatnie
	dni (lookback_days) od najnowszej partycji w tabeli, więc spóźnione eventy wchodzą bez duplikatów.
	Liczone od _dbt_max_partition (zmienna, którą dbt deklaruje w skrypcie insert_overwrite), a nie od
	CURRENT_DATE(), żeby kilkudniowa przerwa w harmonogramie nie zostawiła dziury w danych.

	hours_to_expiration=none — nadpisuje 1 h z dbt_project.yml; inaczej w dev tabela znika przed
	kolejnym przebiegiem i ścieżka incremental nigdy się nie wykonuje.

	Strażnik logiki: przyrostowy przebieg z NOWĄ logiką nadpisałby tylko ostatnie dni i zostawił
	w tabeli mieszankę starej i nowej logiki, bez błędu. Dlatego post_hook zapisuje w etykiecie
	tabeli sumę kontrolną tego pliku, a przebieg przyrostowy z inną sumą przerywa się błędem —
	niezależnie od tego, czy odpala go deploy, harmonogram czy laptop. Pełny rebuild
	(--full-refresh) ustawia nową sumę. Suma liczy się z całego pliku, więc zmiana samego
	komentarza też wymaga --full-refresh.
#}
{%- set lookback_days = 3 -%}

{{
	config(
		materialized='incremental',
		incremental_strategy='insert_overwrite',
		hours_to_expiration=none,
		on_schema_change='append_new_columns',
		post_hook="ALTER TABLE {{ this }} SET OPTIONS (labels = [('logic_checksum', '{{ model.checksum.checksum[:40] }}')])",
		partition_by={
			"field": "event_date",
			"data_type": "date",
			"granularity": "day"
		}
	)
}}

{%- if execute and is_incremental() %}
	{%- set label_sql %}
		SELECT REGEXP_EXTRACT(option_value, r'"logic_checksum", "([0-9a-f]+)"')
		FROM `{{ this.database }}`.`{{ this.schema }}`.INFORMATION_SCHEMA.TABLE_OPTIONS
		WHERE table_name = '{{ this.identifier }}' AND option_name = 'labels'
	{%- endset %}
	{%- set stored_checksum = run_query(label_sql).columns[0].values() | first %}
	{%- if stored_checksum != model.checksum.checksum[:40] %}
		{{ exceptions.raise_compiler_error(
			"stg_ga4__events: logika modelu zmieniła się od ostatniego pełnego rebuildu. "
			~ "Przyrostowy przebieg zostawiłby mieszankę starej i nowej logiki. "
			~ "Odpal dbt build -s stg_ga4__events+ --full-refresh "
			~ "(GitHub: Actions → dbt build → Run workflow → full_refresh)."
		) }}
	{%- endif %}
{%- endif %}

WITH source AS (
	SELECT
		-- event_date z kolumny, nie z _TABLE_SUFFIX: w tabelach dziennych to ta sama data, a pod
		-- --empty (CI przed unit testami) dbt owija źródło w podzapytanie bez pseudokolumn
		PARSE_DATE('%Y%m%d', event_date) AS event_date,
		TIMESTAMP_MICROS(event_timestamp) AS event_ts,
		user_pseudo_id,
		event_name,
		event_params

	FROM {{ source('ga4', 'events') }}
	-- Consent Mode bez zgody na analytics_storage wysyła eventy bez user_pseudo_id; bez filtra
	-- wszyscy tacy użytkownicy zlewają się w jednego z wariantem i zakupami wielu osób
	WHERE user_pseudo_id IS NOT NULL
	{%- if not flags.EMPTY %}
		-- filtry na _TABLE_SUFFIX ze stałymi ograniczają, które tabele dzienne BigQuery w ogóle czyta;
		-- 8 cyfr odcina events_intraday_*
		AND REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')
		{%- if is_incremental() %}
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(_dbt_max_partition, INTERVAL {{ lookback_days }} DAY))
		{%- else %}
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE '{{ var("ga4_start_date") }}')
		{%- endif %}
	{%- endif %}
),

event_tests AS (
	-- Para (test, wariant) z eventu. Testy w różnych slotach trwają równolegle, więc jeden event
	-- może nieść kilka par:
	-- - ab_assign przypisuje do jednego testu: para z ab_test/ab_variant, a parametry slotów
	--   (doklejane do każdego eventu przez Ustawienia zdarzeń) należą tu do INNYCH testów;
	-- - pozostałe eventy: każdy parametr o nazwie slotu (ab1…ab10) z wariantem jako wartością.
	SELECT
		event_date,
		event_ts,
		user_pseudo_id,
		event_name,
		IF(
			event_name = 'ab_assign',
			ARRAY(
				SELECT AS STRUCT
					(SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test') AS ab_test,
					(SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_variant') AS ab_variant
			),
			ARRAY(
				SELECT AS STRUCT
					key AS ab_test,
					value.string_value AS ab_variant
				FROM UNNEST(event_params)
				WHERE REGEXP_CONTAINS(key, r'^ab\d+$')
					AND value.string_value IS NOT NULL
			)
		) AS tests

	FROM source
)

-- Ziarno: event × test. Event bez testu zostaje jednym wierszem z NULL-ami tylko wtedy,
-- gdy jest konwersją — int_ab__conversions bierze wariant z ekspozycji, nie z zakupu.
SELECT
	e.event_date,
	e.event_ts,
	e.user_pseudo_id,
	e.event_name,
	t.ab_test,
	t.ab_variant

FROM event_tests AS e
LEFT JOIN UNNEST(e.tests) AS t
WHERE t.ab_variant IS NOT NULL
	OR e.event_name IN (SELECT conversion_event FROM {{ ref('stg_seeds__ab_tests') }})
