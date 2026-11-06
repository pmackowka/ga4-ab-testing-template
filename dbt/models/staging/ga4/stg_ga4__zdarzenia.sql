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
		ecommerce.transaction_id AS id_transakcji

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
	Przykładowy wynik (dane syntetyczne). Ostatnie dwa wiersze to jeden event z dwoma slotami
	(ab4 na karcie produktu i ab5 na checkoucie trwają równolegle); purchase bez slotu zostaje,
	bo jest eventem konwersji z seeda:
	data_zdarzenia | czas_zdarzenia      | id_uzytkownika | nazwa_zdarzenia | przychod | id_transakcji | slot | wariant
	2026-09-08     | 2026-09-08 10:00:00 | 1234.5678      | ab_assign       | NULL     | NULL          | ab2  | v1
	2026-09-08     | 2026-09-08 10:02:13 | 1234.5678      | view_item       | NULL     | NULL          | ab2  | v1
	2026-09-12     | 2026-09-12 18:30:00 | 9999.0009      | purchase        | 249.90   | T-100231      | NULL | NULL
	2026-11-03     | 2026-11-03 09:15:40 | 4444.0003      | view_item       | NULL     | NULL          | ab4  | v0
	2026-11-03     | 2026-11-03 09:15:40 | 4444.0003      | view_item       | NULL     | NULL          | ab5  | v1
#}
