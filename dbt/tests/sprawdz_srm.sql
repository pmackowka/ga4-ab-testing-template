-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
{#
	SRM (sample ratio mismatch): podział użytkowników między kontrolę a wariant odbiega od 50/50 bardziej,
	niż tłumaczy przypadek. Ta sama reguła co w kalkulatorze „Po teście A/B” (srmCheck): para
	kontrola–wariant, χ² z 1 stopniem swobody, alarm przy p < 0,001, czyli χ² > 10,828.
	Dla pary χ² = Σ(obs − exp)²/exp z exp = (a + b)/2 upraszcza się do (a − b)²/(a + b).
	Zakłada równy podział ruchu między warianty, jak wszystkie tagi z gtm/.
#}
{{ config(severity='warn') }}
	{# warn, nie error: SRM unieważnia wynik, ale o szukaniu błędu w tagu decyduje człowiek — build się kończy, wiersze wyniku pokazują parę do sprawdzenia #}

WITH pary AS (
	SELECT
		v.id_testu,
		v.wariant,
		c.uzytkownicy AS uzytkownicy_kontrola,
		v.uzytkownicy AS uzytkownicy_wariant,
		-- SAFE_DIVIDE zwraca NULL zamiast błędu dzielenia przez zero (test bez użytkowników)
		SAFE_DIVIDE(POW(c.uzytkownicy - v.uzytkownicy, 2), c.uzytkownicy + v.uzytkownicy) AS chi2

	-- self-join: ta sama tabela dwa razy — v to wiersze wariantów, c wiersz kontroli tego samego testu
	FROM {{ ref('fct_wyniki_testow_ab') }} AS v
	JOIN {{ ref('fct_wyniki_testow_ab') }} AS c
		ON c.id_testu = v.id_testu
		AND c.czy_kontrola
	WHERE NOT v.czy_kontrola
)

SELECT *

FROM pary
WHERE chi2 > 10.828
