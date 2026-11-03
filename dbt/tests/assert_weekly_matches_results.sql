-- SINGULAR

-- Test singular: sprawdza, czy DANE są poprawne. Plik .sql w tests/, każdy zwrócony wiersz = błąd.
-- Biegnie w dbt build po modelach, z których czyta (deploy, harmonogram); CI go nie odpala.
-- Ostatni tydzień fct_ab_test_weekly musi dać te same liczby co fct_ab_test_results — inaczej
-- jeden z modeli inaczej liczy wykluczenia albo konwersje. Wiersz = rozjazd.
SELECT
	r.test_id,
	r.variant,
	r.users,
	w.users AS users_weekly,
	r.converters,
	w.converters AS converters_weekly,
	r.excluded_mixed,
	w.excluded_mixed AS excluded_mixed_weekly

FROM {{ ref('fct_ab_test_results') }} AS r
JOIN {{ ref('stg_seeds__ab_tests') }} AS t
	USING (test_id)
JOIN {{ ref('fct_ab_test_weekly') }} AS w
	ON w.test_id = r.test_id
	AND w.variant = r.variant
	AND w.week_end = t.test_end
WHERE r.users != w.users
	OR r.converters != w.converters
	OR r.excluded_mixed != w.excluded_mixed
