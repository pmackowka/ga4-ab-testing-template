DECLARE window_end DATE DEFAULT DATE '2026-09-06';
DECLARE window_weeks INT64 DEFAULT 2;

ASSERT EXTRACT(DAYOFWEEK FROM window_end) = 1
  AS 'window_end musi być niedzielą: okno z pełnych tygodni przed poniedziałkowym startem';
ASSERT (
  SELECT COUNT(DISTINCT _TABLE_SUFFIX)
  FROM `ab-test-sandbox.ga4_syntetyczny.events_*`
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
  FROM `ab-test-sandbox.ga4_syntetyczny.events_*`
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

purchases AS (
  SELECT
    e.user_pseudo_id,
    p.order_key,
    MIN(p.week_no) AS week_no,
    ARRAY_AGG(p.revenue IGNORE NULLS ORDER BY p.event_timestamp LIMIT 1)[SAFE_OFFSET(0)] AS revenue
  FROM events AS p
  JOIN exposed AS e
    ON e.user_pseudo_id = p.user_pseudo_id
    AND p.event_timestamp > e.first_view_ts
  WHERE p.event_name = 'purchase'
  GROUP BY e.user_pseudo_id, p.order_key
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
