{#
	Staging: eventy GA4 potrzebne do testów A/B — z wariantem jakiegokolwiek testu (parametr slotu
	ab1…ab10 albo ab_assign) i eventy konwersji z seeds/rejestr_testow.csv. Reszta ruchu nie trafia
	do tabeli, więc jest mała mimo dużego eksportu.

	Przyrost: każdy przebieg nadpisuje w całości ostatnie dni_wstecz dni od najnowszej partycji
	w tabeli (_dbt_max_partition — zmienna, którą dbt deklaruje w skrypcie insert_overwrite), a nie
	od CURRENT_DATE(), żeby kilkudniowa przerwa w harmonogramie nie zostawiła dziury w danych.

	Strażnik logiki: przyrostowy przebieg z NOWĄ logiką nadpisałby tylko ostatnie dni i zostawił
	w tabeli mieszankę starej i nowej logiki, bez błędu. Blok niżej porównuje sumę kontrolną pliku
	z etykietą tabeli (zapisuje ją post_hook) i przerywa przebieg przy różnicy — niezależnie od tego,
	czy odpala go deploy, harmonogram czy laptop. Suma liczy się z całego pliku, więc zmiana samego
	komentarza też wymaga --full-refresh.
#}
{%- set dni_wstecz = 3 -%}
	{# GA4 dopisuje do dziennej tabeli jeszcze do 72 h #}

{{ config(materialized='incremental') }}
	{# tabela dopisywana przyrostowo, nie przeliczana od zera #}
{{ config(incremental_strategy='insert_overwrite') }}
	{# podmienia całe partycje-dni; merge odpada, bo eksport GA4 nie ma klucza gwarantującego unikalność zdarzenia — powody w README #}
{{ config(hours_to_expiration=none) }}
	{# bez wygasania, wbrew 1 h z dbt_project.yml — inaczej w dev tabela znika i ścieżka incremental nigdy się nie wykonuje #}
{{ config(on_schema_change='append_new_columns') }}
	{# nowa kolumna w modelu dochodzi do tabeli bez pełnego rebuildu #}
{{ config(post_hook="ALTER TABLE {{ this }} SET OPTIONS (labels = [('suma_logiki', '{{ model.checksum.checksum[:40] }}')])") }}
	{# po każdym buildzie zapisuje sumę kontrolną pliku w etykiecie tabeli; --full-refresh ustawia nową #}
{{ config(partition_by={"field": "data_zdarzenia", "data_type": "date", "granularity": "day"}) }}
	{# partycja = dzień z kolumny data_zdarzenia: jednostka nadpisywania i filtr ograniczający skan #}

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

{#
	Przykładowy wynik (dane syntetyczne). Ostatnie dwa wiersze to jeden event z dwoma slotami
	(ab3 na karcie produktu i ab4 na checkoucie trwają równolegle); purchase bez slotu zostaje,
	bo jest eventem konwersji z seeda:
	data_zdarzenia | czas_zdarzenia      | id_uzytkownika | nazwa_zdarzenia | slot | wariant
	2026-09-08     | 2026-09-08 10:00:00 | 1234.5678      | ab_assign       | ab1  | v1
	2026-09-08     | 2026-09-08 10:02:13 | 1234.5678      | view_item       | ab1  | v1
	2026-09-12     | 2026-09-12 18:30:00 | 9999.0009      | purchase        | NULL | NULL
	2026-11-03     | 2026-11-03 09:15:40 | 4444.0003      | view_item       | ab3  | v0
	2026-11-03     | 2026-11-03 09:15:40 | 4444.0003      | view_item       | ab4  | v1
#}
