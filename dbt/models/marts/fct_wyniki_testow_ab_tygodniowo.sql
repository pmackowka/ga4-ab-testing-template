{#
	Te same liczby co fct_wyniki_testow_ab, narastająco na koniec każdego tygodnia testu — pod testy
	sekwencyjne, gdzie decyzję podejmuje się w zaplanowanych punktach kontrolnych. Przy zwykłym
	teście z ustaloną długością to tylko podgląd: decyzja na podstawie tygodnia 2 z 4 zawyża
	odsetek fałszywych zwycięzców (README w katalogu głównym, krok 5).

	Stan „na koniec tygodnia w”: użytkownik ponownie wylosowany w tygodniu 3 jest w tygodniach 1–2
	zwykłym użytkownikiem, a od tygodnia 3 trafia do wykluczeni_mieszani. Ostatni tydzień zgadza się
	z fct_wyniki_testow_ab (tests/sprawdz_zgodnosc_tygodniowych_z_wynikiem.sql).
#}
WITH testy AS (
	SELECT * FROM {{ ref('stg_seeds__rejestr_testow') }}
),

tygodnie AS (
	-- tylko tygodnie, które już się zaczęły
	SELECT
		t.id_testu,
		nr_tygodnia,
		DATE_ADD(t.start_testu, INTERVAL 7 * nr_tygodnia - 1 DAY) AS koniec_tygodnia

	FROM testy AS t
	CROSS JOIN UNNEST(GENERATE_ARRAY(1, DIV(t.dni_testu, 7))) AS nr_tygodnia
	WHERE DATE_ADD(t.start_testu, INTERVAL 7 * (nr_tygodnia - 1) DAY) <= CURRENT_DATE()
),

szkielet AS (
	-- warianty z wyniku końcowego, więc także obcy wariant z danych
	SELECT
		r.id_testu,
		r.slot,
		r.wariant,
		w.nr_tygodnia,
		w.koniec_tygodnia

	FROM {{ ref('fct_wyniki_testow_ab') }} AS r
	JOIN tygodnie AS w
		USING (id_testu)
),

uzytkownicy AS (
	SELECT
		x.id_testu,
		x.wariant,
		x.data_pierwszej_ekspozycji,
		x.data_mieszania,
		c.data_pierwszej_konwersji

	FROM {{ ref('int_ab__ekspozycje') }} AS x
	LEFT JOIN {{ ref('int_ab__konwersje') }} AS c
		USING (id_testu, id_uzytkownika)
)

SELECT
	s.id_testu,
	s.slot,
	s.wariant,
	s.nr_tygodnia,
	s.koniec_tygodnia,
	-- data_pierwszej_ekspozycji IS NOT NULL: wariant bez użytkowników daje z LEFT JOIN jeden wiersz z NULL-ami
	COUNTIF(
		u.data_pierwszej_ekspozycji IS NOT NULL
		AND (u.data_mieszania IS NULL OR u.data_mieszania > s.koniec_tygodnia)
	) AS uzytkownicy,
	COUNTIF(
		(u.data_mieszania IS NULL OR u.data_mieszania > s.koniec_tygodnia)
		AND u.data_pierwszej_konwersji <= s.koniec_tygodnia
	) AS konwertujacy,
	COUNTIF(u.data_mieszania <= s.koniec_tygodnia) AS wykluczeni_mieszani,
	-- tydzień zamknięty, gdy GA4 nie dopisze już danych do jego ostatniego dnia
	s.koniec_tygodnia <= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY) AS czy_koncowy

FROM szkielet AS s
LEFT JOIN uzytkownicy AS u
	ON u.id_testu = s.id_testu
	AND u.wariant = s.wariant
	AND u.data_pierwszej_ekspozycji <= s.koniec_tygodnia
GROUP BY s.id_testu, s.slot, s.wariant, s.nr_tygodnia, s.koniec_tygodnia
