{# Rejestr testów z seeda; listy jako ARRAY. #}
SELECT
	CONCAT(slot, '_', FORMAT_DATE('%Y%m%d', start_testu)) AS id_testu,
	slot,
	start_testu,
	koniec_testu,
	wariant_kontrolny,
	SPLIT(warianty, '|') AS warianty,
	zdarzenie_konwersji,
	SPLIT(zdarzenia_ekspozycji, '|') AS zdarzenia_ekspozycji,
	DATE_DIFF(koniec_testu, start_testu, DAY) + 1 AS dni_testu,
	koniec_testu <= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY) AS czy_koncowy

FROM {{ ref('rejestr_testow') }}

{#
	Przykładowy wynik (czy_koncowy na 2026-11-03):
	id_testu     | slot | start_testu | koniec_testu | wariant_kontrolny | warianty     | zdarzenie_konwersji | zdarzenia_ekspozycji        | dni_testu | czy_koncowy
	ab1_20260824 | ab1  | 2026-08-24  | 2026-09-06   | v0                | [v0, v1]     | purchase            | [ab_assign, view_item]      | 14        | true
	ab2_20260907 | ab2  | 2026-09-07  | 2026-09-20   | v0                | [v0, v1]     | purchase            | [ab_assign, view_item]      | 14        | true
	ab3_20261005 | ab3  | 2026-10-05  | 2026-11-01   | v0                | [v0, v1, v2] | purchase            | [ab_assign, view_item]      | 28        | false
	ab4_20261102 | ab4  | 2026-11-02  | 2026-12-13   | v0                | [v0, v1]     | purchase            | [ab_assign, view_item]      | 42        | false
	ab5_20261102 | ab5  | 2026-11-02  | 2026-11-29   | v0                | [v0, v1]     | purchase            | [ab_assign, begin_checkout] | 28        | false
#}
