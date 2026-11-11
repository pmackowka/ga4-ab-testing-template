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
