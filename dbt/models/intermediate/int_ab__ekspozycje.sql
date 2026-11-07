{#
	Wiersz = test × eksponowany użytkownik: pierwsza ekspozycja, jej wariant i dzień.
	liczba_wariantow 2+ = ponowne losowanie w inny wariant.
	liczba_przydzialow = ab_assign o różnym czasie: 2+ = ponowne losowanie, 0 = nowe _ga albo zgubiony hit.
#}
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

{#
	Przykładowy wynik (dane syntetyczne):
	id_testu     | slot | id_uzytkownika | wariant | czas_pierwszej_ekspozycji | data_pierwszej_ekspozycji | liczba_wariantow | liczba_przydzialow
	ab2_20260907 | ab2  | 1234.5678      | v1      | 2026-09-08 10:00:00       | 2026-09-08                | 1                | 1
	ab2_20260907 | ab2  | 2222.0001      | v0      | 2026-09-09 08:15:00       | 2026-09-09                | 1                | 1
	ab2_20260907 | ab2  | 3333.0002      | v1      | 2026-09-10 20:41:00       | 2026-09-10                | 2                | 2
	ab2_20260907 | ab2  | 4444.0003      | v0      | 2026-09-15 12:00:00       | 2026-09-15                | 1                | 0
	ab2_20260907 | ab2  | 5555.0004      | v0      | 2026-09-16 18:20:00       | 2026-09-16                | 1                | 2
	ab5_20261102 | ab5  | 1234.5678      | v1      | 2026-11-02 09:00:00       | 2026-11-02                | 1                | 1
#}
