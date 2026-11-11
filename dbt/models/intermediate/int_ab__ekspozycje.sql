WITH zdarzenia_testow AS (
	SELECT
		t.id_testu,
		t.slot,
		e.id_uzytkownika,
		e.data_zdarzenia,
		e.czas_zdarzenia,
		e.nazwa_zdarzenia,
		e.wariant,
		e.nazwa_zdarzenia IN UNNEST(t.zdarzenia_ekspozycji) AS czy_ekspozycja

	FROM {{ ref('stg_ga4__zdarzenia') }} AS e
	JOIN {{ ref('stg_seeds__rejestr_testow') }} AS t
		ON e.slot = t.slot
		AND e.data_zdarzenia BETWEEN t.start_testu AND t.koniec_testu
	WHERE e.wariant IS NOT NULL
),

pierwsza_ekspozycja AS (
	SELECT
		id_testu,
		slot,
		id_uzytkownika,
		ARRAY_AGG(
			IF(czy_ekspozycja, STRUCT(czas_zdarzenia, data_zdarzenia, wariant), NULL)
			IGNORE NULLS ORDER BY czas_zdarzenia LIMIT 1
		)[SAFE_OFFSET(0)] AS fe,
		COUNT(DISTINCT wariant) AS liczba_wariantow,
		COUNT(DISTINCT IF(nazwa_zdarzenia = 'ab_assign', czas_zdarzenia, NULL)) AS liczba_przydzialow

	FROM zdarzenia_testow
	GROUP BY id_testu, slot, id_uzytkownika
)

SELECT
	id_testu,
	slot,
	id_uzytkownika,
	fe.wariant AS wariant,
	fe.czas_zdarzenia AS czas_pierwszej_ekspozycji,
	fe.data_zdarzenia AS data_pierwszej_ekspozycji,
	liczba_wariantow,
	liczba_przydzialow

FROM pierwsza_ekspozycja
WHERE fe IS NOT NULL
