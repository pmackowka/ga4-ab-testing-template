-- SINGULAR

{#
	SRM: podział kontrola–wariant odbiega od 50/50 bardziej niż przypadek. Ta sama reguła co
	w kalkulatorze: χ² = (a − b)² / (a + b), alarm przy χ² > 10,828 (p < 0,001).
#}
{{ config(severity='warn') }}

WITH pary AS (
	SELECT
		v.id_testu,
		v.wariant,
		c.uzytkownicy AS uzytkownicy_kontrola,
		v.uzytkownicy AS uzytkownicy_wariant,
		SAFE_DIVIDE(POW(c.uzytkownicy - v.uzytkownicy, 2), c.uzytkownicy + v.uzytkownicy) AS chi2

	FROM {{ ref('fct_wyniki_testow_ab') }} AS v
	JOIN {{ ref('fct_wyniki_testow_ab') }} AS c
		ON c.id_testu = v.id_testu
		AND c.czy_kontrola
	WHERE NOT v.czy_kontrola
)

SELECT *

FROM pary
WHERE chi2 > 10.828

{#
	Przykładowy wynik (ostrzeżenie):
	id_testu     | wariant | uzytkownicy_kontrola | uzytkownicy_wariant | chi2
	ab2_20260907 | v1      | 10850                | 10198               | 20.2
#}
