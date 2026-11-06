{#
	Jeden wiersz na test (id_testu) i użytkownika, który skonwertował PO pierwszej ekspozycji, w oknie testu.
	Wiersz = osoba, nie zamówienie: zdublowany purchase (odświeżona strona podziękowania) nie
	zawyża wyniku. Event konwersji nie musi mieć parametru slotu — wariant jest z ekspozycji.
	przychod = suma zamówień tej osoby, każde id_transakcji raz: staging ma wiersz na event i slot,
	więc zakup z parametrami dwóch slotów jest tam dwa razy, a odświeżona strona podziękowania
	wysyła ten sam zakup ponownie. Zakup bez id_transakcji liczy się raz na event.
#}
WITH zakupy AS (
	SELECT
		x.id_testu,
		x.id_uzytkownika,
		e.czas_zdarzenia,
		e.data_zdarzenia,
		e.przychod

	FROM {{ ref('int_ab__ekspozycje') }} AS x
	JOIN {{ ref('stg_seeds__rejestr_testow') }} AS t
		USING (id_testu)
	JOIN {{ ref('stg_ga4__zdarzenia') }} AS e
		ON e.id_uzytkownika = x.id_uzytkownika
		AND e.nazwa_zdarzenia = t.zdarzenie_konwersji
		AND e.czas_zdarzenia > x.czas_pierwszej_ekspozycji
		AND e.data_zdarzenia <= t.koniec_testu
	QUALIFY ROW_NUMBER() OVER (
		PARTITION BY x.id_testu, x.id_uzytkownika, IFNULL(e.id_transakcji, CAST(e.czas_zdarzenia AS STRING))
		ORDER BY e.czas_zdarzenia
	) = 1
)

SELECT
	id_testu,
	id_uzytkownika,
	MIN(czas_zdarzenia) AS czas_pierwszej_konwersji,
	ARRAY_AGG(data_zdarzenia ORDER BY czas_zdarzenia LIMIT 1)[OFFSET(0)] AS data_pierwszej_konwersji,
	IFNULL(SUM(przychod), 0) AS przychod

FROM zakupy
GROUP BY id_testu, id_uzytkownika

{#
	Przykładowy wynik (dane syntetyczne) — tylko użytkownicy z konwersją, jeden wiersz na osobę i test:
	id_testu     | id_uzytkownika | czas_pierwszej_konwersji | data_pierwszej_konwersji | przychod
	ab2_20260907 | 1234.5678      | 2026-09-12 18:30:00      | 2026-09-12               | 249.90
	ab2_20260907 | 3333.0002      | 2026-09-11 07:05:00      | 2026-09-11               | 118.00
	ab2_20260907 | 4444.0003      | 2026-09-16 21:47:00      | 2026-09-16               | 534.40
	ab2_20260907 | 5555.0004      | 2026-09-30 13:12:00      | 2026-09-30               | 89.99
	ab3_20261005 | 6666.0005      | 2026-10-07 10:20:00      | 2026-10-07               | 1210.00
#}
