-- Rejestr testów z listami jako ARRAY — modele niżej używają IN UNNEST zamiast parsować tekst.
SELECT
	-- slot wraca w kolejnych testach, więc kluczem jest slot + przebieg (= RUN w tagu)
	CONCAT(slot, '_', FORMAT_DATE('%Y%m%d', start_testu)) AS id_testu,
	slot,
	start_testu,
	koniec_testu,
	wariant_kontrolny,
	SPLIT(warianty, '|') AS warianty,
	zdarzenie_konwersji,
	SPLIT(zdarzenia_ekspozycji, '|') AS zdarzenia_ekspozycji,
	DATE_DIFF(koniec_testu, start_testu, DAY) + 1 AS dni_testu,
	-- GA4 dopisuje dane do 72 h: wcześniej wynik zaniża ostatnie dni (ASSERT w sql/03)
	koniec_testu <= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY) AS czy_koncowy

FROM {{ ref('rejestr_testow') }}

{#
	Przykładowy wynik (seed ma dziś 4 testy; czy_koncowy liczone na 2026-11-03):
	id_testu     | slot | start_testu | koniec_testu | wariant_kontrolny | warianty     | zdarzenie_konwersji | zdarzenia_ekspozycji        | dni_testu | czy_koncowy
	ab1_20260907 | ab1  | 2026-09-07  | 2026-10-04   | v0                | [v0, v1]     | purchase            | [ab_assign, view_item]      | 28        | true
	ab2_20261005 | ab2  | 2026-10-05  | 2026-11-01   | v0                | [v0, v1, v2] | purchase            | [ab_assign, view_item]      | 28        | false
	ab3_20261102 | ab3  | 2026-11-02  | 2026-12-13   | v0                | [v0, v1]     | purchase            | [ab_assign, view_item]      | 42        | false
	ab4_20261102 | ab4  | 2026-11-02  | 2026-11-29   | v0                | [v0, v1]     | purchase            | [ab_assign, begin_checkout] | 28        | false
#}
