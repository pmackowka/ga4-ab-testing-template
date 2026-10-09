/*
 04 · PO TEŚCIE — przychód do przeliczenia wzrostu na złotówki
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/

 Przychód z 30 dni przed testem od użytkowników, którzy obejrzeli kartę
 produktu — z zakupów PO pierwszym view_item:
   monthly_revenue → Miesięczny przychód ze strony testowej
 Kalkulator mnoży go przez zakres wzrostu, nie przez jedną liczbę.
*/

DECLARE window_end DATE DEFAULT DATE '2020-12-06';  -- dzień przed startem testu
DECLARE window_days INT64 DEFAULT 30;

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    -- przykładowy eksport ma USD; własny eksport: ecommerce.purchase_revenue
    ecommerce.purchase_revenue_in_usd AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE(
        '%Y%m%d',
        DATE_SUB(window_end, INTERVAL window_days - 1 DAY)
      )
      AND FORMAT_DATE('%Y%m%d', window_end)
    AND event_name IN ('view_item', 'purchase')
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
  -- tylko zakupy po pierwszym obejrzeniu karty produktu
  SELECT
    p.user_pseudo_id,
    p.revenue
  FROM events AS p
  JOIN exposed AS e
    ON e.user_pseudo_id = p.user_pseudo_id
    AND p.event_timestamp > e.first_view_ts
  WHERE p.event_name = 'purchase'
)

SELECT
  window_days AS days,
  (SELECT COUNT(*) FROM exposed) AS users_on_test_page,
  COUNT(DISTINCT user_pseudo_id) AS buyers,
  COUNT(*) AS purchases,
  CAST(ROUND(IFNULL(SUM(revenue), 0)) AS INT64) AS monthly_revenue
FROM purchases;

/*
 Przykładowy wynik (liczby poglądowe):

 days | users_on_test_page | buyers | purchases | monthly_revenue
 -----+--------------------+--------+-----------+----------------
   30 |             80 000 |  1 600 |     1 840 |         500 000

 → kalkulator: Miesięczny przychód ze strony testowej = 500 000.
   Przy domyślnym wyniku testu: od +23 055 zł do +127 965 zł miesięcznie,
   najbardziej prawdopodobnie +75 510 zł.
*/
