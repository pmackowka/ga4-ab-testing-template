{#
	Wynik testu do kalkulatora „Po teście A/B” — jeden wiersz na test i wariant (odpowiednik sql/03).
	Spine z seeda: wariant bez ani jednego użytkownika zostaje jako wiersz z zerami, zamiast zniknąć
	z wyniku. FULL JOIN: wariant z danych, którego nie ma w seedzie, też zostaje i zatrzymuje build
	na teście wariant_w_seedzie. sql/03 robi to samo funkcją ERROR().
	Kontrola jakości, poza kalkulatorem: wykluczeni_mieszani (2+ warianty, wyjęci z wyniku),
	ponownie_przydzieleni (2+ losowania, także w ten sam wariant — zostają w wyniku, jeśli wariant
	się nie zmienił) i bez_przydzialu (wariant z ciasteczka bez ab_assign: nowe _ga, więc ta sama osoba
	może być policzona dwa razy, albo zgubiony hit ab_assign). Niewidoczny zostaje przypadek, gdy znikają naraz _ga i ciasteczko
	testu: nowy użytkownik z nowym losowaniem.
#}
WITH testy AS (
	SELECT * FROM {{ ref('stg_seeds__rejestr_testow') }}
),

warianty_seeda AS (
	SELECT
		t.id_testu,
		wariant

	FROM testy AS t
	CROSS JOIN UNNEST(t.warianty) AS wariant
),

zaobserwowane AS (
	SELECT
		x.id_testu,
		x.wariant,
		COUNTIF(x.liczba_wariantow = 1) AS uzytkownicy,
		COUNTIF(x.liczba_wariantow = 1 AND c.id_uzytkownika IS NOT NULL) AS konwertujacy,
		COUNTIF(x.liczba_wariantow > 1) AS wykluczeni_mieszani,
		COUNTIF(x.liczba_przydzialow > 1) AS ponownie_przydzieleni,
		COUNTIF(x.liczba_przydzialow = 0) AS bez_przydzialu

	FROM {{ ref('int_ab__ekspozycje') }} AS x
	LEFT JOIN {{ ref('int_ab__konwersje') }} AS c
		USING (id_testu, id_uzytkownika)
	GROUP BY x.id_testu, x.wariant
)

SELECT
	id_testu,
	t.slot,
	wariant,
	wariant = t.wariant_kontrolny AS czy_kontrola,
	IF(wariant = t.wariant_kontrolny, 'A (kontrola)', CONCAT('B (wariant ', wariant, ')'))
		AS pole_kalkulatora,
	IFNULL(o.uzytkownicy, 0) AS uzytkownicy,
	IFNULL(o.konwertujacy, 0) AS konwertujacy,
	IFNULL(o.wykluczeni_mieszani, 0) AS wykluczeni_mieszani,
	IFNULL(o.ponownie_przydzieleni, 0) AS ponownie_przydzieleni,
	IFNULL(o.bez_przydzialu, 0) AS bez_przydzialu,
	t.czy_koncowy

FROM warianty_seeda
FULL JOIN zaobserwowane AS o
	USING (id_testu, wariant)
JOIN testy AS t
	USING (id_testu)

{#
	Przykładowy wynik (dane syntetyczne) — uzytkownicy i konwertujacy idą do kalkulatora „Po teście A/B”,
	ale tylko przy czy_koncowy = true (tu: ab2):
	id_testu     | slot | wariant | czy_kontrola | pole_kalkulatora | uzytkownicy | konwertujacy | wykluczeni_mieszani | ponownie_przydzieleni | bez_przydzialu | czy_koncowy
	ab2_20260907 | ab2  | v0      | true         | A (kontrola)     | 10234       | 412          | 37                  | 76                    | 118            | true
	ab2_20260907 | ab2  | v1      | false        | B (wariant v1)   | 10198       | 455          | 41                  | 80                    | 109            | true
	ab3_20261005 | ab3  | v0      | true         | A (kontrola)     | 9870        | 380          | 22                  | 47                    | 96             | false
	ab3_20261005 | ab3  | v1      | false        | B (wariant v1)   | 9912        | 401          | 25                  | 51                    | 101            | false
	ab3_20261005 | ab3  | v2      | false        | B (wariant v2)   | 9801        | 366          | 19                  | 40                    | 93             | false
#}
