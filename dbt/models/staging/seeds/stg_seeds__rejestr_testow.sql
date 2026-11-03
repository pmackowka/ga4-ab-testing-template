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
