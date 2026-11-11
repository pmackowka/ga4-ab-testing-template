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
