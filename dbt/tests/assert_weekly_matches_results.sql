-- Ostatni tydzień fct_ab_test_weekly musi dać te same liczby co fct_ab_test_results — inaczej
-- jeden z modeli inaczej liczy wykluczenia albo konwersje. Wiersz = rozjazd.
SELECT
	r.test_name,
	r.variant,
	r.users,
	w.users AS users_weekly,
	r.converters,
	w.converters AS converters_weekly,
	r.excluded_mixed,
	w.excluded_mixed AS excluded_mixed_weekly

FROM {{ ref('fct_ab_test_results') }} AS r
JOIN {{ ref('stg_seeds__ab_tests') }} AS t
	USING (test_name)
JOIN {{ ref('fct_ab_test_weekly') }} AS w
	ON w.test_name = r.test_name
	AND w.variant = r.variant
	AND w.week_end = t.test_end
WHERE r.users != w.users
	OR r.converters != w.converters
	OR r.excluded_mixed != w.excluded_mixed
