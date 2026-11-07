/*
 02 · PRZYCHÓD TYGODNIOWY → pole przychodu w obu kalkulatorach
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/
 Test karty produktu: wejście = view_item, przychód z purchase.
 Tabelę `twoj-projekt.analytics_123456789.events_*` podmień w obu miejscach.

 Parametry:
 - window_end: niedziela przed startem testu
 - window_weeks: to samo okno co max_weeks w 01

 Przychód z zakupów po pierwszym view_item, zamówienie raz na transaction_id.
 Mediana wyraźnie niższa od średniej = w oknie był pik (Black Friday):
 do kalkulatora bierz medianę.
*/

DECLARE window_end DATE DEFAULT DATE '2026-09-06';
DECLARE window_weeks INT64 DEFAULT 5;

ASSERT EXTRACT(DAYOFWEEK FROM window_end) = 1
  AS 'window_end musi być niedzielą: okno z pełnych tygodni przed poniedziałkowym startem';
ASSERT (
  SELECT COUNT(DISTINCT _TABLE_SUFFIX)
  FROM `twoj-projekt.analytics_123456789.events_*`
  WHERE _TABLE_SUFFIX BETWEEN
      FORMAT_DATE('%Y%m%d', DATE_SUB(window_end, INTERVAL window_weeks * 7 - 1 DAY))
    AND FORMAT_DATE('%Y%m%d', window_end)
) = window_weeks * 7
  AS 'brakuje dziennych tabel eksportu w oknie';

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    DIV(DATE_DIFF(
        PARSE_DATE('%Y%m%d', event_date),
        DATE_SUB(window_end, INTERVAL window_weeks * 7 - 1 DAY),
        DAY), 7) + 1
      AS week_no,
    ecommerce.purchase_revenue AS revenue,
    IFNULL(
      NULLIF(NULLIF(ecommerce.transaction_id, '(not set)'), ''),
      CONCAT(user_pseudo_id, '-', CAST(event_timestamp AS STRING))
    ) AS order_key
  FROM `twoj-projekt.analytics_123456789.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE(
        '%Y%m%d',
        DATE_SUB(window_end, INTERVAL window_weeks * 7 - 1 DAY)
      )
      AND FORMAT_DATE('%Y%m%d', window_end)
    AND event_name IN ('view_item', 'purchase')
    AND user_pseudo_id IS NOT NULL
),

exposed AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_view_ts
  FROM events
  WHERE event_name = 'view_item'
  GROUP BY user_pseudo_id
),

orders AS (
  SELECT user_pseudo_id, event_timestamp, week_no, revenue
  FROM events
  WHERE event_name = 'purchase'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY order_key ORDER BY event_timestamp) = 1
),

purchases AS (
  SELECT
    p.week_no,
    p.revenue
  FROM orders AS p
  JOIN exposed AS e
    ON e.user_pseudo_id = p.user_pseudo_id
    AND p.event_timestamp > e.first_view_ts
),

weekly AS (
  SELECT
    w AS week_no,
    IFNULL(SUM(p.revenue), 0) AS revenue
  FROM UNNEST(GENERATE_ARRAY(1, window_weeks)) AS w
  LEFT JOIN purchases AS p
    ON p.week_no = w
  GROUP BY w
)

SELECT
  CAST(ROUND(SUM(revenue) / window_weeks) AS INT64) AS weekly_revenue,
  CAST(ROUND(ANY_VALUE(median_revenue)) AS INT64) AS weekly_revenue_median
FROM (
  SELECT
    revenue,
    PERCENTILE_CONT(revenue, 0.5) OVER () AS median_revenue
  FROM weekly
);

/*
 Przykładowy wynik (4 tygodnie po 100 000 i Black Friday 225 000):
 weekly_revenue | weekly_revenue_median
 ---------------+----------------------
        125 000 |               100 000

 Kalkulator: Tygodniowy przychód ze strony testowej.
*/
