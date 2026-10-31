{#
	Te same liczby co fct_ab_test_results, narastająco na koniec każdego tygodnia testu — pod testy
	sekwencyjne, gdzie decyzję podejmuje się w zaplanowanych punktach kontrolnych. Przy zwykłym
	teście z ustaloną długością to tylko podgląd: decyzja na podstawie tygodnia 2 z 4 zawyża
	odsetek fałszywych zwycięzców (README w katalogu głównym, krok 5).

	Stan „na koniec tygodnia w”: użytkownik ponownie wylosowany w tygodniu 3 jest w tygodniach 1–2
	zwykłym użytkownikiem, a od tygodnia 3 trafia do excluded_mixed. Ostatni tydzień zgadza się
	z fct_ab_test_results (tests/assert_weekly_matches_results.sql).
#}
WITH tests AS (
	SELECT * FROM {{ ref('stg_seeds__ab_tests') }}
),

weeks AS (
	-- tylko tygodnie, które już się zaczęły
	SELECT
		t.test_name,
		week_no,
		DATE_ADD(t.test_start, INTERVAL 7 * week_no - 1 DAY) AS week_end

	FROM tests AS t
	CROSS JOIN UNNEST(GENERATE_ARRAY(1, DIV(t.test_days, 7))) AS week_no
	WHERE DATE_ADD(t.test_start, INTERVAL 7 * (week_no - 1) DAY) <= CURRENT_DATE()
),

spine AS (
	-- warianty z wyniku końcowego, więc także obcy wariant z danych
	SELECT
		r.test_name,
		r.variant,
		w.week_no,
		w.week_end

	FROM {{ ref('fct_ab_test_results') }} AS r
	JOIN weeks AS w
		USING (test_name)
),

users AS (
	SELECT
		x.test_name,
		x.variant,
		x.first_exposure_date,
		x.mixed_date,
		c.first_conversion_date

	FROM {{ ref('int_ab__exposures') }} AS x
	LEFT JOIN {{ ref('int_ab__conversions') }} AS c
		USING (test_name, user_pseudo_id)
)

SELECT
	s.test_name,
	s.variant,
	s.week_no,
	s.week_end,
	-- first_exposure_date IS NOT NULL: wariant bez użytkowników daje z LEFT JOIN jeden wiersz z NULL-ami
	COUNTIF(
		u.first_exposure_date IS NOT NULL
		AND (u.mixed_date IS NULL OR u.mixed_date > s.week_end)
	) AS users,
	COUNTIF(
		(u.mixed_date IS NULL OR u.mixed_date > s.week_end)
		AND u.first_conversion_date <= s.week_end
	) AS converters,
	COUNTIF(u.mixed_date <= s.week_end) AS excluded_mixed,
	-- tydzień zamknięty, gdy GA4 nie dopisze już danych do jego ostatniego dnia
	s.week_end <= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY) AS is_final

FROM spine AS s
LEFT JOIN users AS u
	ON u.test_name = s.test_name
	AND u.variant = s.variant
	AND u.first_exposure_date <= s.week_end
GROUP BY s.test_name, s.variant, s.week_no, s.week_end
