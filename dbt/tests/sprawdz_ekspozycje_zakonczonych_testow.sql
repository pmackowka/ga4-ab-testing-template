SELECT
	t.id_testu,
	'zakończony test bez ani jednej ekspozycji — sprawdź tag, parametr slotu i zdarzenia_ekspozycji' AS powod

FROM {{ ref('stg_seeds__rejestr_testow') }} AS t
LEFT JOIN {{ ref('int_ab__ekspozycje') }} AS x
	USING (id_testu)
WHERE t.czy_koncowy
	AND x.id_testu IS NULL
