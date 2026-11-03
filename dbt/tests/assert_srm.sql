-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
{#
	SRM (sample ratio mismatch): podział users między kontrolę a wariant odbiega od 50/50 bardziej,
	niż tłumaczy przypadek. Ta sama reguła co w kalkulatorze „Po teście A/B” (srmCheck): para
	kontrola–wariant, χ² z 1 stopniem swobody, alarm przy p < 0,001, czyli χ² > 10,828.
	Dla pary χ² = Σ(obs − exp)²/exp z exp = (a + b)/2 upraszcza się do (a − b)²/(a + b).
	Zakłada równy podział ruchu między warianty, jak wszystkie tagi z gtm/.

	warn, nie error: SRM unieważnia wynik, ale o tym, czy szukać błędu w tagu, decyduje człowiek —
	build ma się skończyć, a wiersze wyniku pokazują, którą parę sprawdzić.
#}
{{ config(severity='warn') }}

WITH pairs AS (
	SELECT
		v.test_id,
		v.variant,
		c.users AS users_control,
		v.users AS users_variant,
		SAFE_DIVIDE(POW(c.users - v.users, 2), c.users + v.users) AS chi2

	FROM {{ ref('fct_ab_test_results') }} AS v
	JOIN {{ ref('fct_ab_test_results') }} AS c
		ON c.test_id = v.test_id
		AND c.is_control
	WHERE NOT v.is_control
)

SELECT *

FROM pairs
WHERE chi2 > 10.828
