{#
	Staging: eventy GA4 potrzebne do testów A/B — z wariantem jakiegokolwiek testu (parametr slotu
	ab1…ab10 albo ab_assign) i eventy konwersji z seeds/rejestr_testow.csv. Reszta ruchu nie trafia
	do tabeli, więc jest mała mimo dużego eksportu.

	Przyrost: każdy przebieg nadpisuje w całości ostatnie dni_wstecz dni od najnowszej partycji
	w tabeli (_dbt_max_partition — zmienna, którą dbt deklaruje w skrypcie insert_overwrite), a nie
	od CURRENT_DATE(), żeby kilkudniowa przerwa w harmonogramie nie zostawiła dziury w danych.

	Zmiana logiki tego pliku wymaga --full-refresh: przebieg przyrostowy nadpisałby tylko ostatnie
	dni i zostawił w tabeli mieszankę starej i nowej logiki, bez błędu.

	Jinja w tym pliku — dbt najpierw renderuje Jinja do czystego SQL (wynik: target/compiled/…),
	dopiero ten SQL idzie do BigQuery:
	- { # … # } komentarz Jinja (tu ze spacjami, bo prawdziwe # } zamknęłoby ten komentarz): znika
	  przy kompilacji; -- to komentarz SQL i zostaje w skompilowanym kodzie
	- {{ … }} wstawia wartość do SQL, np. nazwę tabeli z source() albo liczbę z dni_wstecz
	- {% … %} instrukcja (set, if) — decyduje, jaki SQL powstanie, sama niczego nie wstawia
	- minus przy nawiasie ({%- albo -%}) usuwa białe znaki i entery z tej strony, żeby
	  skompilowany SQL nie miał pustych linii po instrukcjach
	Uwaga: w komentarzu -- Jinja nadal działa, więc nawiasy klamrowe opisuj tylko w komentarzu Jinja.
#}
{%- set dni_wstecz = 3 -%}
	{# zmienna Jinja, nie SQL: niżej {{ dni_wstecz }} wstawia w kod liczbę 3; GA4 dopisuje do dziennej tabeli jeszcze do 72 h #}

{{ config(materialized='incremental') }}
	{# config() w pliku modelu wygrywa z +materialized: view z dbt_project.yml; tabela dopisywana przyrostowo, nie przeliczana od zera #}
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
		{#
			source('ga4', 'zdarzenia') = tabela z _ga4__zrodla.yml, po kompilacji
			`twoj-projekt`.`analytics_123456789`.`events_*`. Zamiast wpisanej nazwy, bo z source()
			dbt rysuje lineage (dbt docs) i bierze projekt i dataset z vars — jedno miejsce do podmiany.
		#}
	-- Consent Mode bez zgody na analytics_storage wysyła eventy bez user_pseudo_id; bez filtra
	-- wszyscy tacy użytkownicy zlewają się w jednego z wariantem i zakupami wielu osób
	WHERE user_pseudo_id IS NOT NULL
	{#
		flags.EMPTY = true, gdy dbt biegnie z flagą --empty (CI buduje modele bez danych, żeby unit
		testy znały typy kolumn). Wtedy dbt zamienia source() na podzapytanie
		(select * from `…events_*` where false limit 0) — zero wierszy, zero kosztu. Pseudokolumna
		_TABLE_SUFFIX istnieje tylko bezpośrednio na tabeli wildcard, nie w podzapytaniu, więc filtry
		niżej dałyby błąd „Unrecognized name: _TABLE_SUFFIX”. Przy --empty cały blok do
		{%- endif %} wypada z SQL; w zwykłym buildzie trafia do niego w całości.
	#}
	{%- if not flags.EMPTY %}
		-- filtry na _TABLE_SUFFIX ze stałymi ograniczają, które tabele dzienne BigQuery w ogóle czyta;
		-- 8 cyfr odcina events_intraday_*
		AND REGEXP_CONTAINS(_TABLE_SUFFIX, r'^\d{8}$')
			{# _TABLE_SUFFIX = część nazwy po events_: '20261105' przechodzi, 'intraday_20261106' odpada #}
		{#
			is_incremental() = true tylko wtedy, gdy tabela modelu już istnieje w BigQuery, model ma
			materialized='incremental' i przebieg jest bez --full-refresh. Pierwszy build albo
			--full-refresh → false → gałąź {%- else %}: czytaj wszystko od ga4_data_startu.
			Kolejne przebiegi → true → czytaj tylko ostatnie dni.

			_dbt_max_partition to nie kolumna, tylko zmienna skryptu BigQuery: dbt-bigquery widzi tę
			nazwę w SQL i dokleja przed zapytaniem DECLARE _dbt_max_partition DATE DEFAULT
			(SELECT MAX(data_zdarzenia) FROM <ta tabela>) — najnowszy dzień, który już jest w tabeli.
			var("ga4_data_startu") wstawia tekst z vars w dbt_project.yml, stąd DATE '…' wokół.
		#}
		{%- if is_incremental() %}
		-- pusta tabela daje _dbt_max_partition = NULL; bez COALESCE filtr nie przepuściłby nic, już na zawsze
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', COALESCE(
			DATE_SUB(_dbt_max_partition, INTERVAL {{ dni_wstecz }} DAY), DATE '{{ var("ga4_data_startu") }}'))
		{#
			Przykład z podstawionymi wartościami: dni_wstecz = 3, ga4_data_startu = '2026-08-24',
			najnowsza partycja w tabeli = 2026-11-05. Po kompilacji Jinja:
				AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', COALESCE(
					DATE_SUB(_dbt_max_partition, INTERVAL 3 DAY), DATE '2026-08-24'))
			W BigQuery: _dbt_max_partition = DATE '2026-11-05' → DATE_SUB daje 2026-11-02 → COALESCE
			zostawia 2026-11-02 (nie NULL) → FORMAT_DATE daje '20261102'. Czyli:
				AND _TABLE_SUFFIX >= '20261102'   — czyta events_20261102 … events_20261105 i nowsze
			Pusta tabela: _dbt_max_partition = NULL → DATE_SUB daje NULL → COALESCE bierze 2026-08-24
			→ _TABLE_SUFFIX >= '20260824'.
		#}
		{%- else %}
		AND _TABLE_SUFFIX >= FORMAT_DATE('%Y%m%d', DATE '{{ var("ga4_data_startu") }}')
			{# po kompilacji: FORMAT_DATE('%Y%m%d', DATE '2026-08-24') → _TABLE_SUFFIX >= '20260824' #}
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
		-- obie gałęzie IF muszą mieć ten sam typ: ARRAY<STRUCT<slot, wariant>>, czyli tablicę par;
		-- dlatego ab_assign też daje tablicę, choć zawsze z jedną parą
		IF(
			nazwa_zdarzenia = 'ab_assign',
			-- ARRAY(SELECT …) zbiera wiersze podzapytania w tablicę; SELECT AS STRUCT skleja kolumny
			-- jednego wiersza w jedną wartość STRUCT (rekord z polami slot i wariant)
			ARRAY(
				SELECT AS STRUCT
					-- event_params to tablica par key/value: UNNEST rozwija ją w wiersze, WHERE key wybiera
					-- jeden parametr, value.string_value to jego wartość tekstowa (liczby są w int_value)
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
-- JOIN z UNNEST tablicy z tego samego wiersza: event z 2 parami daje 2 wiersze. LEFT, nie zwykły
-- JOIN: event z pustą tablicą (purchase bez slotu) zostaje jednym wierszem z t.slot i t.wariant = NULL
LEFT JOIN UNNEST(e.testy) AS t
WHERE t.wariant IS NOT NULL
	-- ref() wskazuje inny model dbt; z ref() dbt ustala kolejność budowy (seed → jego staging → ten model)
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
