/*
 01 · PRZED TESTEM — dane do kalkulatora „Przed testem A/B”
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/

 Test karty produktu: wejście = view_item, konwersja = purchase.
 Kilka pełnych tygodni + wiersz ŚREDNIA, który wpisujesz do kalkulatora:
   users_weekly      → Użytkownicy w tygodniu
   converters_weekly → Konwertujący w tygodniu
 Definicje i pozostałe pola kalkulatora: README.md.
*/

DECLARE first_week_start DATE DEFAULT DATE '2020-11-02';  -- poniedziałek
DECLARE weeks_count INT64 DEFAULT 4;                      -- zalecane: 4 tygodnie

ASSERT EXTRACT(DAYOFWEEK FROM first_week_start) = 2
  AS 'first_week_start musi być poniedziałkiem';

WITH events AS (
  -- _TABLE_SUFFIX ogranicza skanowane dni, czyli koszt zapytania
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week_start
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', first_week_start)
      AND FORMAT_DATE(
        '%Y%m%d',
        DATE_ADD(first_week_start, INTERVAL weeks_count * 7 - 1 DAY)
      )
    AND event_name IN ('view_item', 'purchase')
),

exposed AS (
  -- każdy użytkownik raz na tydzień, z momentem pierwszego view_item
  SELECT
    week_start,
    user_pseudo_id,
    MIN(event_timestamp) AS first_view_ts
  FROM events
  WHERE event_name = 'view_item'
  GROUP BY week_start, user_pseudo_id
),

converted AS (
  -- zakup PO pierwszym view_item, w tym samym tygodniu; DISTINCT = osoby
  SELECT DISTINCT
    e.week_start,
    e.user_pseudo_id
  FROM exposed AS e
  JOIN events AS p
    ON p.user_pseudo_id = e.user_pseudo_id
    AND p.week_start = e.week_start
    AND p.event_name = 'purchase'
    AND p.event_timestamp > e.first_view_ts
),

per_week AS (
  SELECT
    e.week_start,
    COUNT(*) AS users_weekly,
    COUNT(c.user_pseudo_id) AS converters_weekly
  FROM exposed AS e
  LEFT JOIN converted AS c
    USING (week_start, user_pseudo_id)
  GROUP BY e.week_start
)

-- tygodnie: sprawdź, czy są do siebie podobne
SELECT
  CAST(week_start AS STRING) AS week,
  users_weekly,
  converters_weekly,
  ROUND(SAFE_DIVIDE(converters_weekly, users_weekly) * 100, 2) AS cr_pct
FROM per_week

UNION ALL

-- ten wiersz wpisujesz do kalkulatora
SELECT
  'ŚREDNIA → do kalkulatora' AS week,
  CAST(ROUND(AVG(users_weekly)) AS INT64) AS users_weekly,
  CAST(ROUND(AVG(converters_weekly)) AS INT64) AS converters_weekly,
  ROUND(SAFE_DIVIDE(SUM(converters_weekly), SUM(users_weekly)) * 100, 2) AS cr_pct
FROM per_week

ORDER BY week;

/*
 Przykładowy wynik (liczby poglądowe, zgodne z domyślnymi danymi kalkulatora;
 na przykładowym eksporcie GA4 wyjdą inne):

 week                       | users_weekly | converters_weekly | cr_pct
 ---------------------------+--------------+-------------------+-------
 2020-11-02                 |       19 850 |               397 |   2.00
 2020-11-09                 |       20 410 |               402 |   1.97
 2020-11-16                 |       19 630 |               400 |   2.04
 2020-11-23                 |       20 110 |               401 |   1.99
 ŚREDNIA → do kalkulatora   |       20 000 |               400 |   2.00

 → kalkulator: Użytkownicy w tygodniu = 20 000, Konwertujący w tygodniu = 400.
*/
