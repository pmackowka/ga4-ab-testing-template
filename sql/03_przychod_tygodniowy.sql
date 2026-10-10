/*
 03 · PRZYCHÓD TYGODNIOWY → pole przychodu w obu kalkulatorach
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/
 Test karty produktu: wejście = view_item, przychód z purchase.
*/

DECLARE window_end DATE DEFAULT DATE '2020-12-06';  -- dzień przed startem testu
DECLARE window_weeks INT64 DEFAULT 4;  -- pełne tygodnie: każdy dzień tygodnia tyle samo razy

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
        DATE_SUB(window_end, INTERVAL window_weeks * 7 - 1 DAY)
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

/*
 ─── WYNIK ────────────────────────────────────────────────────────────────
 weekly_revenue → kalkulatory: Tygodniowy przychód ze strony testowej

 Przychód z window_weeks tygodni przed testem od użytkowników, którzy
 obejrzeli kartę produktu — tylko z zakupów PO pierwszym view_item —
 podzielony przez liczbę tygodni.

 Przykład (liczby poglądowe):
 weekly_revenue
 --------------
        125 000

 → Przed testem, przy danych domyślnych: w 4 tygodniach wykryjesz
   +14,35%, czyli +17 931 zł tygodniowo.
 → Po teście, przy domyślnym wyniku: od +5 764 zł do +31 991 zł
   tygodniowo, najbardziej prawdopodobnie +18 878 zł.
*/
SELECT
  CAST(ROUND(IFNULL(SUM(revenue), 0) / window_weeks) AS INT64) AS weekly_revenue
FROM purchases;
