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
	Przychód na użytkownika do kalkulatora w trybie „Przychód na użytkownika”: przychod / uzytkownicy
	i odchylenie_przychodu liczone po osobach z uzytkownicy, razem z zerami. Przychód osoby jest
	przycięty do 99,9 percentyla przychodu konwertujących w teście (oba warianty razem), żeby jedno
	duże zamówienie nie przesądziło wyniku; przychod w wierszu to suma po przycięciu.
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

uzytkownicy_testu AS (
	SELECT
		x.*,
		c.id_uzytkownika IS NOT NULL AS czy_konwersja,
		IF(x.liczba_wariantow = 1,
			LEAST(IFNULL(c.przychod, 0), IFNULL(PERCENTILE_CONT(
				IF(x.liczba_wariantow = 1 AND c.przychod > 0, c.przychod, NULL), 0.999
			) OVER (PARTITION BY x.id_testu), 0)),
			NULL) AS przychod

	FROM {{ ref('int_ab__ekspozycje') }} AS x
	LEFT JOIN {{ ref('int_ab__konwersje') }} AS c
		USING (id_testu, id_uzytkownika)
),

zaobserwowane AS (
	SELECT
		id_testu,
		wariant,
		COUNTIF(liczba_wariantow = 1) AS uzytkownicy,
		COUNTIF(liczba_wariantow = 1 AND czy_konwersja) AS konwertujacy,
		SUM(przychod) AS przychod,
		STDDEV_SAMP(przychod) AS odchylenie_przychodu,
		COUNTIF(liczba_wariantow > 1) AS wykluczeni_mieszani,
		COUNTIF(liczba_przydzialow > 1) AS ponownie_przydzieleni,
		COUNTIF(liczba_przydzialow = 0) AS bez_przydzialu

	FROM uzytkownicy_testu
	GROUP BY id_testu, wariant
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
	ROUND(IFNULL(o.przychod, 0), 2) AS przychod,
	ROUND(IFNULL(SAFE_DIVIDE(o.przychod, o.uzytkownicy), 0), 2) AS przychod_na_uzytkownika,
	ROUND(IFNULL(o.odchylenie_przychodu, 0), 2) AS odchylenie_przychodu,
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
	Przykładowy wynik (dane syntetyczne) — uzytkownicy i konwertujacy (albo przychod_na_uzytkownika
	i odchylenie_przychodu) idą do kalkulatora „Po teście A/B”,
	ale tylko przy czy_koncowy = true (tu: ab2):
	id_testu     | slot | wariant | czy_kontrola | pole_kalkulatora | uzytkownicy | konwertujacy | przychod   | przychod_na_uzytkownika | odchylenie_przychodu | wykluczeni_mieszani | ponownie_przydzieleni | bez_przydzialu | czy_koncowy
	ab2_20260907 | ab2  | v0      | true         | A (kontrola)     | 10234       | 412          | 98880.00   | 9.66                    | 62.40                | 37                  | 76                    | 118            | true
	ab2_20260907 | ab2  | v1      | false        | B (wariant v1)   | 10198       | 455          | 109200.00  | 10.71                   | 65.90                | 41                  | 80                    | 109            | true
	ab3_20261005 | ab3  | v0      | true         | A (kontrola)     | 9870        | 380          | 91200.00   | 9.24                    | 61.10                | 22                  | 47                    | 96             | false
	ab3_20261005 | ab3  | v1      | false        | B (wariant v1)   | 9912        | 401          | 96240.00   | 9.71                    | 62.80                | 25                  | 51                    | 101            | false
	ab3_20261005 | ab3  | v2      | false        | B (wariant v2)   | 9801        | 366          | 87840.00   | 8.96                    | 60.20                | 19                  | 40                    | 93             | false
#}
