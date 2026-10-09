/*
================================================================================
 02 · PRZED TESTEM — sprawdzenie dla testu dłuższego niż tydzień
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/
================================================================================

 Po co: kalkulator liczy czas testu tak, jakby co tydzień przychodzili NOWI
 użytkownicy: 4 tygodnie = 4 × „Użytkownicy w tygodniu”. W praktyce część ludzi
 wraca, więc unikalnych użytkowników w 4 tygodniach jest mniej. Jednocześnie
 CR rośnie, bo powracający mają więcej czasu na konwersję.

 To zapytanie liczy oba zjawiska na Twoich danych, w oknie tak długim jak
 planowany test. Wynik mówi, o ile kalkulator jest optymistyczny co do czasu.

 ─── Jak czytać wynik ───────────────────────────────────────────────────────

 users_window              unikalni użytkownicy w całym oknie (np. 4 tygodnie)
 users_sum_of_weeks        suma użytkowników z kolejnych tygodni — tyle zakłada
                           kalkulator
 overlap_factor            users_window / users_sum_of_weeks; 0,80 znaczy, że
                           w oknie jest o 20% mniej ludzi, niż zakłada kalkulator
 converters_window         konwertujący w całym oknie (po pierwszym wejściu)
 cr_window_pct             CR liczony na całym oknie — zwykle wyższy niż tygodniowy

 ─── Co z tym zrobić w kalkulatorze ─────────────────────────────────────────

 Najprościej: wpisz jako „Użytkownicy w tygodniu” wartość
   users_window / test_weeks            ← kolumna users_weekly_effective
 a jako „Konwertujący w tygodniu”
   converters_window / test_weeks       ← kolumna converters_weekly_effective
 Kalkulator dostanie wtedy realną liczbę unikalnych użytkowników na tydzień
 testu i CR z okna o długości testu. Jeśli wyjdzie inny czas niż przy danych
 z zapytania 01 — wierz temu.

 Domyślnie: publiczny przykładowy eksport GA4 (2020-11-01 – 2021-01-31).
================================================================================
*/

-- ─── Parametry ────────────────────────────────────────────────────────────────

-- poniedziałek — początek okna o długości planowanego testu
DECLARE window_start DATE DEFAULT DATE '2020-11-02';
-- planowana długość testu w pełnych tygodniach (pole „Najdłużej możesz testować”)
DECLARE test_weeks INT64 DEFAULT 4;
DECLARE exposure_event STRING DEFAULT 'view_item';
DECLARE conversion_event STRING DEFAULT 'purchase';

ASSERT EXTRACT(DAYOFWEEK FROM window_start) = 2
  AS 'window_start musi być poniedziałkiem';

-- ─── Zapytanie ────────────────────────────────────────────────────────────────

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
    AND event_name IN (exposure_event, conversion_event)
),

-- całe okno: każdy użytkownik raz, z pierwszym wejściem w oknie
exposed_window AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_exposure_ts
  FROM events
  WHERE event_name = exposure_event
  GROUP BY user_pseudo_id
),

converted_window AS (
  SELECT DISTINCT e.user_pseudo_id
  FROM exposed_window AS e
  JOIN events AS c
    ON c.user_pseudo_id = e.user_pseudo_id
    AND c.event_name = conversion_event
    AND c.event_timestamp > e.first_exposure_ts
),

-- dla porównania: suma tygodniowych liczb, czyli założenie kalkulatora
weekly_users AS (
  SELECT
    week_start,
    COUNT(DISTINCT user_pseudo_id) AS users_weekly
  FROM events
  WHERE event_name = exposure_event
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
  -- do wpisania w kalkulator zamiast wartości z zapytania 01
  CAST(ROUND((SELECT COUNT(*) FROM exposed_window) / test_weeks) AS INT64)
    AS users_weekly_effective,
  CAST(ROUND((SELECT COUNT(*) FROM converted_window) / test_weeks) AS INT64)
    AS converters_weekly_effective;
