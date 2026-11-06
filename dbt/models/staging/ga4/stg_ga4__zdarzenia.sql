{#
	Staging: eventy GA4 potrzebne do testów A/B — z wariantem jakiegokolwiek testu (parametr slotu
	ab1…ab10 albo ab_assign) i eventy konwersji z seeds/rejestr_testow.csv. Reszta ruchu nie trafia
	do tabeli, więc jest mała mimo dużego eksportu.

	Przyrost: każdy przebieg nadpisuje w całości ostatnie dni_wstecz dni od najnowszej partycji
	w tabeli (_dbt_max_partition — zmienna, którą dbt deklaruje w skrypcie insert_overwrite), a nie
	od CURRENT_DATE(), żeby kilkudniowa przerwa w harmonogramie nie zostawiła dziury w danych.

	Zmiana logiki tego pliku wymaga --full-refresh: przebieg przyrostowy nadpisałby tylko ostatnie
	dni i zostawił w tabeli mieszankę starej i nowej logiki, bez błędu.

	Co jest w zmiennych (przykładowe wartości):
	- dni_wstecz = 3
	- var("ga4_data_startu") = '2026-08-24' — z vars w dbt_project.yml
	- _dbt_max_partition = DATE '2026-11-05' — najnowszy dzień w tabeli; NULL, gdy tabela jest pusta
	- flags.EMPTY = false w zwykłym buildzie, true przy dbt build --empty (CI)
	- is_incremental() = false przy pierwszym buildzie i --full-refresh, true w kolejnych przebiegach
	Po podstawieniu filtr przyrostowy to _TABLE_SUFFIX >= '20261102', pełny rebuild: >= '20260824'.
#}
{%- set dni_wstecz = 3 -%}
	{# GA4 dopisuje do dziennej tabeli jeszcze do 72 h #}

{{ config(materialized='incremental') }}
	{# tabela dopisywana przyrostowo, nie przeliczana od zera #}
{{ config(incremental_strategy='insert_overwrite') }}
	{# podmienia całe partycje-dni; merge odpada, bo eksport GA4 nie ma klucza gwarantującego unikalność zdarzenia — powody w README #}
{{ config(partition_by={"field": "data_zdarzenia", "data_type": "date", "granularity": "day"}) }}
	{# partycja = dzień z kolumny data_zdarzenia: jednostka nadpisywania i filtr ograniczający skan #}

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
		-- pusta tabela daje _dbt_max_partition = NULL; bez COALESCE filtr nie przepuściłby nic, już na zawsze
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', COALESCE(
			DATE_SUB(_dbt_max_partition, INTERVAL {{ dni_wstecz }} DAY), DATE '{{ var("ga4_data_startu") }}'))
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
					-- zmienna GTM „Własny plik cookie” wysyła surową wartość ciasteczka, także 'out'
					-- z tagu 03 (użytkownik poza testem) — to nie wariant, więc nie wchodzi do analizy
					AND value.string_value != 'out'
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
	(ab4 na karcie produktu i ab5 na checkoucie trwają równolegle); purchase bez slotu zostaje,
	bo jest eventem konwersji z seeda:
	data_zdarzenia | czas_zdarzenia      | id_uzytkownika | nazwa_zdarzenia | slot | wariant
	2026-09-08     | 2026-09-08 10:00:00 | 1234.5678      | ab_assign       | ab2  | v1
	2026-09-08     | 2026-09-08 10:02:13 | 1234.5678      | view_item       | ab2  | v1
	2026-09-12     | 2026-09-12 18:30:00 | 9999.0009      | purchase        | NULL | NULL
	2026-11-03     | 2026-11-03 09:15:40 | 4444.0003      | view_item       | ab4  | v0
	2026-11-03     | 2026-11-03 09:15:40 | 4444.0003      | view_item       | ab5  | v1
#}
