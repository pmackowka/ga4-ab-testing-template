{#
	Jeden wiersz na test (test_id) i eksponowanego użytkownika: pierwsza ekspozycja, jej wariant i dzień
	oraz pierwszy event z INNYM wariantem (ponowne losowanie po utracie cookie). Liczy wszystkie
	testy z seeda naraz — okno i eventy ekspozycji biorą się z wiersza testu, nie z DECLARE.
#}
WITH test_events AS (
	-- slot + okno testu wskazują jeden przebieg: okna testów w tym samym slocie się nie nakładają
	SELECT
		t.test_id,
		t.test_name,
		e.user_pseudo_id,
		e.event_date,
		e.event_ts,
		e.ab_variant,
		e.event_name IN UNNEST(t.exposure_events) AS is_exposure

	FROM {{ ref('stg_ga4__events') }} AS e
	JOIN {{ ref('stg_seeds__ab_tests') }} AS t
		ON e.ab_test = t.test_name
		AND e.event_date BETWEEN t.test_start AND t.test_end
	WHERE e.ab_variant IS NOT NULL
),

first_exposure AS (
	-- STRUCT w ARRAY_AGG: czas, dzień i wariant z TEGO SAMEGO eventu, bez osobnego MIN i joina
	SELECT
		test_id,
		test_name,
		user_pseudo_id,
		ARRAY_AGG(
			IF(is_exposure, STRUCT(event_ts, event_date, ab_variant), NULL)
			IGNORE NULLS ORDER BY event_ts LIMIT 1
		)[SAFE_OFFSET(0)] AS fe,
		COUNT(DISTINCT ab_variant) AS variants_seen

	FROM test_events
	GROUP BY test_id, test_name, user_pseudo_id
),

exposed AS (
	-- użytkownik z wariantem tylko na eventach spoza exposure_events nie wchodzi do testu
	SELECT
		test_id,
		test_name,
		user_pseudo_id,
		fe.ab_variant AS variant,
		fe.event_ts AS first_exposure_ts,
		fe.event_date AS first_exposure_date,
		variants_seen

	FROM first_exposure
	WHERE fe IS NOT NULL
),

mixed AS (
	-- pierwszy event z wariantem innym niż w pierwszej ekspozycji, także sprzed niej;
	-- istnieje dokładnie wtedy, gdy variants_seen > 1
	SELECT
		x.test_id,
		x.user_pseudo_id,
		MIN(e.event_date) AS mixed_date

	FROM exposed AS x
	JOIN test_events AS e
		ON e.test_id = x.test_id
		AND e.user_pseudo_id = x.user_pseudo_id
		AND e.ab_variant != x.variant
	GROUP BY x.test_id, x.user_pseudo_id
)

SELECT
	x.test_id,
	x.test_name,
	x.user_pseudo_id,
	x.variant,
	x.first_exposure_ts,
	x.first_exposure_date,
	x.variants_seen,
	m.mixed_date

FROM exposed AS x
LEFT JOIN mixed AS m
	USING (test_id, user_pseudo_id)
