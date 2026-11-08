/*
 01 · PRZED TESTEM → kalkulator „Przed testem A/B”
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/
 Test karty produktu: wejście = view_item, konwersja = purchase.
 Tabela w obu miejscach: `ab-test-sandbox.ga4_syntetyczny.events_*` (dane syntetyczne); własny eksport GA4: `twoj-projekt.analytics_123456789.events_*`.

 Każdy wiersz to okno k tygodni: osoba liczy się raz, od pierwszego view_item,
 z zakupami do końca okna — tak jak w wyniku testu. Zamówienie raz na
 transaction_id. Przychód osoby przycięty do 99,9 percentyla kupujących.
 Jak użyć: wpisz wiersz z planowaną liczbą tygodni. Kalkulator policzył inny
 czas? Weź wiersz z tym czasem i przelicz, aż czas zgodzi się z wierszem.
*/

-- ===== DO UZUPEŁNIENIA: tylko te zmienne edytujesz, niżej nic nie zmieniaj =====
DECLARE window_start DATE DEFAULT DATE '2026-08-24';  -- liczysz z rejestru: `start_testu` planowanego testu minus 7 × max_weeks dni, poniedziałek, od którego liczysz ruch przed testem
DECLARE max_weeks INT64 DEFAULT 2;  -- Twoja decyzja, nie kolumna rejestru: ile tygodni okna policzyć (1–8, tyle co limit w kalkulatorze); wynik ma wiersz dla 1…max_weeks
DECLARE test_start DATE DEFAULT DATE '2026-09-07';  -- = `start_testu` z rejestr_testow.csv: poniedziałek, w którym ruszy test (domyślnie ab2); okno musi się skończyć przed nim
-- ===== KONIEC =====

ASSERT EXTRACT(DAYOFWEEK FROM window_start) = 2
  AS 'window_start musi być poniedziałkiem';
ASSERT max_weeks BETWEEN 1 AND 8
  AS 'max_weeks: od 1 do 8 tygodni';
ASSERT DATE_ADD(window_start, INTERVAL max_weeks * 7 DAY) <= test_start
  AS 'okno sięga w okres testu: przesuń window_start wstecz albo zmniejsz max_weeks';
ASSERT (
  SELECT COUNT(DISTINCT _TABLE_SUFFIX)
  FROM `ab-test-sandbox.ga4_syntetyczny.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', window_start)
    AND FORMAT_DATE('%Y%m%d', DATE_ADD(window_start, INTERVAL max_weeks * 7 - 1 DAY))
) = max_weeks * 7
  AS 'brakuje dziennych tabel eksportu w oknie';

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    NULLIF(NULLIF(ecommerce.transaction_id, '(not set)'), '') AS transaction_id,
    ecommerce.purchase_revenue AS revenue,
    DIV(DATE_DIFF(PARSE_DATE('%Y%m%d', event_date), window_start, DAY), 7) + 1
      AS week_no
  FROM `ab-test-sandbox.ga4_syntetyczny.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', window_start)
      AND FORMAT_DATE(
        '%Y%m%d',
        DATE_ADD(window_start, INTERVAL max_weeks * 7 - 1 DAY)
      )
    AND event_name IN ('view_item', 'purchase')
    AND user_pseudo_id IS NOT NULL
),

first_view AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_view_ts,
    MIN(week_no) AS first_week
  FROM events
  WHERE event_name = 'view_item'
  GROUP BY user_pseudo_id
),

user_purchases AS (
  SELECT
    f.user_pseudo_id,
    IFNULL(p.transaction_id, CAST(p.event_timestamp AS STRING)) AS transaction_key,
    MIN(p.week_no) AS week_no,
    ANY_VALUE(p.revenue) AS revenue
  FROM first_view AS f
  JOIN events AS p
    ON p.user_pseudo_id = f.user_pseudo_id
    AND p.event_name = 'purchase'
    AND p.event_timestamp > f.first_view_ts
  GROUP BY f.user_pseudo_id, transaction_key
),

users_windows AS (
  SELECT
    w AS weeks,
    f.user_pseudo_id,
    LOGICAL_OR(up.week_no <= w) AS converted,
    IFNULL(SUM(IF(up.week_no <= w, up.revenue, 0)), 0) AS revenue
  FROM UNNEST(GENERATE_ARRAY(1, max_weeks)) AS w
  JOIN first_view AS f
    ON f.first_week <= w
  LEFT JOIN user_purchases AS up
    ON up.user_pseudo_id = f.user_pseudo_id
  GROUP BY w, f.user_pseudo_id
),

windows AS (
  SELECT
    weeks,
    COUNT(*) AS users_unique,
    COUNTIF(converted) AS converters,
    AVG(revenue_capped) AS revenue_per_user,
    STDDEV_SAMP(revenue_capped) AS revenue_sd
  FROM (
    SELECT
      *,
      LEAST(revenue, IFNULL(PERCENTILE_CONT(IF(revenue > 0, revenue, NULL), 0.999)
        OVER (PARTITION BY weeks), 0)) AS revenue_capped
    FROM users_windows
  )
  GROUP BY weeks
)

SELECT
  weeks,
  CAST(ROUND(users_unique / weeks) AS INT64) AS users_per_week,
  CAST(ROUND(converters / weeks) AS INT64) AS converters_per_week,
  ROUND(revenue_per_user, 2) AS revenue_per_user,
  ROUND(revenue_sd, 2) AS revenue_sd
FROM windows
ORDER BY weeks;

/*
 Wynik dla testu ab2 (dane syntetyczne, okno 2026-08-24 – 2026-09-06, domyślne parametry):
 weeks | users_per_week | converters_per_week | revenue_per_user | revenue_sd
 ------+----------------+---------------------+------------------+-----------
     1 |         67 182 |               2 098 |             8.56 |      64.24
     2 |         64 287 |               2 056 |             8.89 |      66.41

 Kalkulator: users_per_week → Użytkownicy w tygodniu, converters_per_week →
 Konwertujący w tygodniu; w trybie przychodu revenue_per_user i revenue_sd
 (dotyczą całego okna, nie tygodnia).
*/
