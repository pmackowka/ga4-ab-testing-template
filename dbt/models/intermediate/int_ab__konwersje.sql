{#
	Jeden wiersz na test (id_testu) i użytkownika, który skonwertował PO pierwszej ekspozycji, w oknie testu.
	Wiersz = osoba, nie zamówienie: zdublowany purchase (odświeżona strona podziękowania) nie
	zawyża wyniku. Event konwersji nie musi mieć parametru slotu — wariant jest z ekspozycji.
#}
SELECT
	x.id_testu,
	x.id_uzytkownika,
	MIN(e.czas_zdarzenia) AS czas_pierwszej_konwersji,
	-- dzień tego samego eventu co czas_pierwszej_konwersji, z sufiksu tabeli (strefa usługi GA4)
	ARRAY_AGG(e.data_zdarzenia ORDER BY e.czas_zdarzenia LIMIT 1)[OFFSET(0)] AS data_pierwszej_konwersji

FROM {{ ref('int_ab__ekspozycje') }} AS x
JOIN {{ ref('stg_seeds__rejestr_testow') }} AS t
	USING (id_testu)
JOIN {{ ref('stg_ga4__zdarzenia') }} AS e
	ON e.id_uzytkownika = x.id_uzytkownika
	AND e.nazwa_zdarzenia = t.zdarzenie_konwersji
	AND e.czas_zdarzenia > x.czas_pierwszej_ekspozycji
	AND e.data_zdarzenia <= t.koniec_testu
GROUP BY x.id_testu, x.id_uzytkownika
