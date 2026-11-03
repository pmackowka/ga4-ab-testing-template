{#
	Jeden wiersz na test (id_testu) i eksponowanego użytkownika: pierwsza ekspozycja, jej wariant i dzień
	oraz pierwszy event z INNYM wariantem (ponowne losowanie po utracie cookie). Liczy wszystkie
	testy z seeda naraz — okno i eventy ekspozycji biorą się z wiersza testu, nie z DECLARE.
#}
WITH zdarzenia_testow AS (
	-- slot + okno testu wskazują jeden przebieg: okna testów w tym samym slocie się nie nakładają
	SELECT
		t.id_testu,
		t.slot,
		e.id_uzytkownika,
		e.data_zdarzenia,
		e.czas_zdarzenia,
		e.wariant,
		e.nazwa_zdarzenia IN UNNEST(t.zdarzenia_ekspozycji) AS czy_ekspozycja

	FROM {{ ref('stg_ga4__zdarzenia') }} AS e
	JOIN {{ ref('stg_seeds__rejestr_testow') }} AS t
		ON e.slot = t.slot
		AND e.data_zdarzenia BETWEEN t.start_testu AND t.koniec_testu
	WHERE e.wariant IS NOT NULL
),

pierwsza_ekspozycja AS (
	-- STRUCT w ARRAY_AGG: czas, dzień i wariant z TEGO SAMEGO eventu, bez osobnego MIN i joina
	SELECT
		id_testu,
		slot,
		id_uzytkownika,
		ARRAY_AGG(
			IF(czy_ekspozycja, STRUCT(czas_zdarzenia, data_zdarzenia, wariant), NULL)
			IGNORE NULLS ORDER BY czas_zdarzenia LIMIT 1
		)[SAFE_OFFSET(0)] AS fe,
		COUNT(DISTINCT wariant) AS liczba_wariantow

	FROM zdarzenia_testow
	GROUP BY id_testu, slot, id_uzytkownika
),

eksponowani AS (
	-- użytkownik z wariantem tylko na eventach spoza zdarzenia_ekspozycji nie wchodzi do testu
	SELECT
		id_testu,
		slot,
		id_uzytkownika,
		fe.wariant AS wariant,
		fe.czas_zdarzenia AS czas_pierwszej_ekspozycji,
		fe.data_zdarzenia AS data_pierwszej_ekspozycji,
		liczba_wariantow

	FROM pierwsza_ekspozycja
	WHERE fe IS NOT NULL
),

mieszani AS (
	-- pierwszy event z wariantem innym niż w pierwszej ekspozycji, także sprzed niej;
	-- istnieje dokładnie wtedy, gdy liczba_wariantow > 1
	SELECT
		x.id_testu,
		x.id_uzytkownika,
		MIN(e.data_zdarzenia) AS data_mieszania

	FROM eksponowani AS x
	JOIN zdarzenia_testow AS e
		ON e.id_testu = x.id_testu
		AND e.id_uzytkownika = x.id_uzytkownika
		AND e.wariant != x.wariant
	GROUP BY x.id_testu, x.id_uzytkownika
)

SELECT
	x.id_testu,
	x.slot,
	x.id_uzytkownika,
	x.wariant,
	x.czas_pierwszej_ekspozycji,
	x.data_pierwszej_ekspozycji,
	x.liczba_wariantow,
	m.data_mieszania

FROM eksponowani AS x
LEFT JOIN mieszani AS m
	USING (id_testu, id_uzytkownika)
