{#
	Jeden wiersz na test i użytkownika, który skonwertował PO pierwszej ekspozycji, w oknie testu.
	Wiersz = osoba, nie zamówienie: zdublowany purchase (odświeżona strona podziękowania) nie
	zawyża wyniku. Event konwersji nie musi mieć parametru ab_test — wariant jest z ekspozycji.
#}
SELECT
	x.test_name,
	x.user_pseudo_id,
	MIN(e.event_ts) AS first_conversion_ts,
	-- dzień tego samego eventu co first_conversion_ts, z sufiksu tabeli (strefa usługi GA4)
	ARRAY_AGG(e.event_date ORDER BY e.event_ts LIMIT 1)[OFFSET(0)] AS first_conversion_date

FROM {{ ref('int_ab__exposures') }} AS x
JOIN {{ ref('stg_seeds__ab_tests') }} AS t
	USING (test_name)
JOIN {{ ref('stg_ga4__events') }} AS e
	ON e.user_pseudo_id = x.user_pseudo_id
	AND e.event_name = t.conversion_event
	AND e.event_ts > x.first_exposure_ts
	AND e.event_date <= t.test_end
GROUP BY x.test_name, x.user_pseudo_id
