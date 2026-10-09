/*
 02 · PRZED TESTEM — poprawka dla testu dłuższego niż tydzień
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/

 Kalkulator zakłada, że co tydzień przychodzą nowi użytkownicy. Część wraca,
 więc w oknie testu unikalnych jest mniej, a CR wyższy. Gdy test ma trwać
 2+ tygodnie, wpisz te wartości zamiast wyniku z 01:
   users_weekly_effective      → Użytkownicy w tygodniu
   converters_weekly_effective → Konwertujący w tygodniu
*/

DECLARE window_start DATE DEFAULT DATE '2020-11-02';  -- poniedziałek
DECLARE test_weeks INT64 DEFAULT 4;                   -- planowana długość testu

ASSERT EXTRACT(DAYOFWEEK FROM window_start) = 2
  AS 'window_start musi być poniedziałkiem';

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week_start
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', window_start)
      AND FORMAT_DATE(
        '%Y%m%d',
        DATE_ADD(window_start, INTERVAL test_weeks * 7 - 1 DAY)
      )
    AND event_name IN ('view_item', 'purchase')
),

-- całe okno: każdy użytkownik raz, z pierwszym view_item
exposed_window AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_view_ts
  FROM events
  WHERE event_name = 'view_item'
  GROUP BY user_pseudo_id
),

-- zakup po pierwszym view_item w oknie; osoby, nie zamówienia
converted_window AS (
  SELECT DISTINCT e.user_pseudo_id
  FROM exposed_window AS e
  JOIN events AS p
    ON p.user_pseudo_id = e.user_pseudo_id
    AND p.event_name = 'purchase'
    AND p.event_timestamp > e.first_view_ts
),

-- założenie kalkulatora: suma tygodniowych liczb
weekly_users AS (
  SELECT
    week_start,
    COUNT(DISTINCT user_pseudo_id) AS users_weekly
  FROM events
  WHERE event_name = 'view_item'
  GROUP BY week_start
)

SELECT
  (SELECT COUNT(*) FROM exposed_window) AS users_window,
  (SELECT SUM(users_weekly) FROM weekly_users) AS users_sum_of_weeks,
  -- 0.80 = w oknie o 20% mniej ludzi, niż zakłada kalkulator
  ROUND(
    SAFE_DIVIDE(
      (SELECT COUNT(*) FROM exposed_window),
      (SELECT SUM(users_weekly) FROM weekly_users)
    ),
    2
  ) AS overlap_factor,
  (SELECT COUNT(*) FROM converted_window) AS converters_window,
  ROUND(
    SAFE_DIVIDE(
      (SELECT COUNT(*) FROM converted_window),
      (SELECT COUNT(*) FROM exposed_window)
    ) * 100,
    2
  ) AS cr_window_pct,
  CAST(ROUND((SELECT COUNT(*) FROM exposed_window) / test_weeks) AS INT64)
    AS users_weekly_effective,
  CAST(ROUND((SELECT COUNT(*) FROM converted_window) / test_weeks) AS INT64)
    AS converters_weekly_effective;

/*
 Przykładowy wynik (liczby poglądowe):

 users_window | users_sum_of_weeks | overlap_factor | converters_window | cr_window_pct | users_weekly_effective | converters_weekly_effective
 -------------+--------------------+----------------+-------------------+---------------+------------------------+----------------------------
       64 000 |             80 000 |           0.80 |             1 760 |          2.75 |                 16 000 |                         440

 → w 4 tygodnie wraca 20% ludzi: kalkulator dostaje 16 000 zamiast 20 000
   użytkowników w tygodniu i CR 2,75% zamiast 2%. Jeśli czas testu wyjdzie
   inny niż z danymi z 01 — wierz temu wynikowi.
*/
