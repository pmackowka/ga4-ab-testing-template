{#
	Staging: eventy GA4 potrzebne do testów A/B — z wariantem jakiegokolwiek testu (parametr slotu
	ab1…ab10 albo ab_assign) i eventy konwersji z seeds/rejestr_testow.csv. Reszta ruchu nie trafia
	do tabeli, więc jest mała mimo dużego eksportu.

	insert_overwrite, nie merge: eksport GA4 nie ma klucza eventu, a jednostką poprawki jest dzień —
	GA4 dopisuje do dziennej tabeli jeszcze do 72 h. Każdy przebieg nadpisuje w całości ostatnie
	dni (dni_wstecz) od najnowszej partycji w tabeli, więc spóźnione eventy wchodzą bez duplikatów.
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
{%- set dni_wstecz = 3 -%}

{{
	config(
		materialized='incremental',
		incremental_strategy='insert_overwrite',
		hours_to_expiration=none,
		on_schema_change='append_new_columns',
		post_hook="ALTER TABLE {{ this }} SET OPTIONS (labels = [('suma_logiki', '{{ model.checksum.checksum[:40] }}')])",
		partition_by={
			"field": "data_zdarzenia",
			"data_type": "date",
			"granularity": "day"
		}
	)
}}

{%- if execute and is_incremental() %}
	{%- set zapytanie_etykiety %}
		SELECT REGEXP_EXTRACT(option_value, r'"suma_logiki", "([0-9a-f]+)"')
		FROM `{{ this.database }}`.`{{ this.schema }}`.INFORMATION_SCHEMA.TABLE_OPTIONS
		WHERE table_name = '{{ this.identifier }}' AND option_name = 'labels'
	{%- endset %}
	{%- set zapisana_suma = run_query(zapytanie_etykiety).columns[0].values() | first %}
	{%- if zapisana_suma != model.checksum.checksum[:40] %}
		{{ exceptions.raise_compiler_error(
			"stg_ga4__zdarzenia: logika modelu zmieniła się od ostatniego pełnego rebuildu. "
			~ "Przyrostowy przebieg zostawiłby mieszankę starej i nowej logiki. "
			~ "Odpal dbt build -s stg_ga4__zdarzenia+ --full-refresh "
			~ "(GitHub: Actions → dbt build → Run workflow → full_refresh)."
		) }}
	{%- endif %}
{%- endif %}

WITH zrodlo AS (
	-- nazwy kolumn GA4 (event_date, user_pseudo_id…) zostają tylko tutaj, dalej polskie
	SELECT
		-- data z kolumny event_date, nie z _TABLE_SUFFIX: w tabelach dziennych to ta sama data, a pod
		-- --empty (CI przed unit testami) dbt owija źródło w podzapytanie bez pseudokolumn
		PARSE_DATE('%Y%m%d', event_date) AS data_zdarzenia,
		TIMESTAMP_MICROS(event_timestamp) AS czas_zdarzenia,
		user_pseudo_id AS id_uzytkownika,
		event_name AS nazwa_zdarzenia,
		event_params AS parametry

	FROM {{ source('ga4', 'zdarzenia') }}
	-- Consent Mode bez zgody na analytics_storage wysyła eventy bez user_pseudo_id; bez filtra
	-- wszyscy tacy użytkownicy zlewają się w jednego z wariantem i zakupami wielu osób
	WHERE user_pseudo_id IS NOT NULL
	{%- if not flags.EMPTY %}
		-- filtry na _TABLE_SUFFIX ze stałymi ograniczają, które tabele dzienne BigQuery w ogóle czyta;
		-- 8 cyfr odcina events_intraday_*
		AND REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')
		{%- if is_incremental() %}
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE_SUB(_dbt_max_partition, INTERVAL {{ dni_wstecz }} DAY))
		{%- else %}
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE '{{ var("ga4_data_startu") }}')
		{%- endif %}
	{%- endif %}
),

testy_zdarzen AS (
	-- Para (test, wariant) z eventu. Testy w różnych slotach trwają równolegle, więc jeden event
	-- może nieść kilka par:
	-- - ab_assign przypisuje do jednego testu: para z ab_test/ab_variant, a parametry slotów
	--   (doklejane do każdego eventu przez Ustawienia zdarzeń) należą tu do INNYCH testów;
	-- - pozostałe eventy: każdy parametr o nazwie slotu (ab1…ab10) z wariantem jako wartością.
	SELECT
		data_zdarzenia,
		czas_zdarzenia,
		id_uzytkownika,
		nazwa_zdarzenia,
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
			)
		) AS testy

	FROM zrodlo
)

-- Ziarno: event × test. Event bez testu zostaje jednym wierszem z NULL-ami tylko wtedy,
-- gdy jest konwersją — int_ab__konwersje bierze wariant z ekspozycji, nie z zakupu.
SELECT
	e.data_zdarzenia,
	e.czas_zdarzenia,
	e.id_uzytkownika,
	e.nazwa_zdarzenia,
	t.slot,
	t.wariant

FROM testy_zdarzen AS e
LEFT JOIN UNNEST(e.testy) AS t
WHERE t.wariant IS NOT NULL
	OR e.nazwa_zdarzenia IN (SELECT zdarzenie_konwersji FROM {{ ref('stg_seeds__rejestr_testow') }})
