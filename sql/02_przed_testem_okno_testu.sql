/*
================================================================================
 02 · PRZED TESTEM — poprawka dla testu dłuższego niż tydzień
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/
================================================================================

 SCENARIUSZ: test karty produktu (view_item → purchase), jak w 01.

 PO CO: kalkulator zakłada, że co tydzień przychodzą NOWI użytkownicy:
 4 tygodnie = 4 × „Użytkownicy w tygodniu”. W praktyce część ludzi wraca na
 karty produktu, więc unikalnych w 4 tygodniach jest mniej. Za to CR rośnie,
 bo powracający mają więcej czasu na zakup. Zapytanie liczy oba zjawiska
 w oknie tak długim jak planowany test.

 ─── Kolumny ────────────────────────────────────────────────────────────────

 users_window                 unikalni z view_item w całym oknie
 users_sum_of_weeks           suma tygodniowych — tyle zakłada kalkulator
 overlap_factor               users_window / users_sum_of_weeks;
                              0,80 = o 20% mniej ludzi, niż zakłada kalkulator
 converters_window            kupujący po pierwszym view_item w oknie
 cr_window_pct                CR z całego okna — zwykle wyższy niż tygodniowy

 ─── Pola kalkulatora z tego zapytania ──────────────────────────────────────

 Użytkownicy w tygodniu   ← users_weekly_effective   (users_window / test_weeks)
 Konwertujący w tygodniu  ← converters_weekly_effective
   Wpisz zamiast wartości z 01, gdy test ma trwać 2+ tygodnie. Kalkulator
   dostaje wtedy realną liczbę unikalnych użytkowników na tydzień testu i CR
   z okna o długości testu. Jeśli czas wyjdzie dłuższy niż z 01 — wierz temu.
================================================================================
*/

-- poniedziałek — początek okna o długości planowanego testu
DECLARE window_start DATE DEFAULT DATE '2020-11-02';
-- planowana długość testu w pełnych tygodniach
DECLARE test_weeks INT64 DEFAULT 4;

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

-- całe okno: każdy użytkownik raz, z pierwszym view_item w oknie
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
  -- do kalkulatora zamiast wartości z 01
  CAST(ROUND((SELECT COUNT(*) FROM exposed_window) / test_weeks) AS INT64)
    AS users_weekly_effective,
  CAST(ROUND((SELECT COUNT(*) FROM converted_window) / test_weeks) AS INT64)
    AS converters_weekly_effective;
