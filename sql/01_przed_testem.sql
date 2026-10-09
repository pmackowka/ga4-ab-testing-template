/*
 01 · PRZED TESTEM — dane do kalkulatora „Przed testem A/B”
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/

 Test karty produktu: wejście = view_item, konwersja = purchase.
 Okna narastające od 1 do 8 tygodni — tak liczy się wynik testu: każdy
 użytkownik raz, od pierwszego wejścia, zakup w całym oknie. Ludzie wracają,
 więc unikalnych przybywa coraz wolniej, a CR rośnie z długością okna.

 Jak użyć: wpisz do kalkulatora wiersz z liczbą tygodni, którą planujesz
   users_weekly_eff      → Użytkownicy w tygodniu
   converters_weekly_eff → Konwertujący w tygodniu
 Jeśli kalkulator policzy inny czas testu — weź wiersz z tym czasem.
 week_users i week_cr_pct: sam ten tydzień — sprawdź, czy tygodnie są podobne.
*/

DECLARE window_start DATE DEFAULT DATE '2020-11-02';  -- poniedziałek
DECLARE max_weeks INT64 DEFAULT 8;

ASSERT EXTRACT(DAYOFWEEK FROM window_start) = 2
  AS 'window_start musi być poniedziałkiem';

WITH events AS (
  -- _TABLE_SUFFIX ogranicza skanowane dni, czyli koszt zapytania
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    DIV(DATE_DIFF(PARSE_DATE('%Y%m%d', event_date), window_start, DAY), 7) + 1
      AS week_no
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', window_start)
      AND FORMAT_DATE(
        '%Y%m%d',
        DATE_ADD(window_start, INTERVAL max_weeks * 7 - 1 DAY)
      )
    AND event_name IN ('view_item', 'purchase')
),

first_view AS (
  -- pierwsze wejście w całym oknie: moment i numer tygodnia
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_view_ts,
    MIN(week_no) AS first_week
  FROM events
  WHERE event_name = 'view_item'
  GROUP BY user_pseudo_id
),

first_purchase AS (
  -- tydzień pierwszego zakupu PO pierwszym wejściu; osoby, nie zamówienia
  SELECT
    f.user_pseudo_id,
    MIN(p.week_no) AS purchase_week
  FROM first_view AS f
  JOIN events AS p
    ON p.user_pseudo_id = f.user_pseudo_id
    AND p.event_name = 'purchase'
    AND p.event_timestamp > f.first_view_ts
  GROUP BY f.user_pseudo_id
),

cumulative AS (
  -- okno k tygodni: weszli w tygodniach 1..k, kupili do końca tygodnia k
  SELECT
    w AS weeks,
    COUNTIF(f.first_week <= w) AS users_unique,
    COUNTIF(f.first_week <= w AND fp.purchase_week <= w) AS converters
  FROM UNNEST(GENERATE_ARRAY(1, max_weeks)) AS w
  CROSS JOIN first_view AS f
  LEFT JOIN first_purchase AS fp
    ON fp.user_pseudo_id = f.user_pseudo_id
  GROUP BY w
),

week_entries AS (
  -- kontrola tygodni: pierwsze wejście w obrębie jednego tygodnia
  SELECT
    week_no,
    user_pseudo_id,
    MIN(event_timestamp) AS first_view_ts
  FROM events
  WHERE event_name = 'view_item'
  GROUP BY week_no, user_pseudo_id
),

week_converted AS (
  -- zakup PO pierwszym wejściu, w tym samym tygodniu; DISTINCT = osoby
  SELECT DISTINCT
    e.week_no,
    e.user_pseudo_id
  FROM week_entries AS e
  JOIN events AS p
    ON p.user_pseudo_id = e.user_pseudo_id
    AND p.week_no = e.week_no
    AND p.event_name = 'purchase'
    AND p.event_timestamp > e.first_view_ts
),

week_alone AS (
  -- sam ten tydzień: użytkownicy i konwertujący
  SELECT
    e.week_no,
    COUNT(*) AS week_users,
    COUNT(c.user_pseudo_id) AS week_converters
  FROM week_entries AS e
  LEFT JOIN week_converted AS c
    USING (week_no, user_pseudo_id)
  GROUP BY e.week_no
)

SELECT
  c.weeks,
  c.users_unique,
  c.converters,
  ROUND(SAFE_DIVIDE(c.converters, c.users_unique) * 100, 2) AS cr_pct,
  CAST(ROUND(c.users_unique / c.weeks) AS INT64) AS users_weekly_eff,
  CAST(ROUND(c.converters / c.weeks) AS INT64) AS converters_weekly_eff,
  wa.week_users,
  ROUND(SAFE_DIVIDE(wa.week_converters, wa.week_users) * 100, 2) AS week_cr_pct
FROM cumulative AS c
LEFT JOIN week_alone AS wa
  ON wa.week_no = c.weeks
ORDER BY c.weeks;

/*
 Przykładowy wynik (liczby poglądowe, wiersz 1 = domyślne dane kalkulatora):

 weeks | users_unique | converters | cr_pct | users_weekly_eff | converters_weekly_eff | week_users | week_cr_pct
 ------+--------------+------------+--------+------------------+-----------------------+------------+------------
     1 |       20 000 |        400 |   2.00 |           20 000 |                   400 |     20 000 |        2.00
     2 |       36 000 |        830 |   2.31 |           18 000 |                   415 |     19 850 |        1.98
     3 |       50 500 |      1 300 |   2.57 |           16 833 |                   433 |     20 410 |        2.02
     4 |       64 000 |      1 760 |   2.75 |           16 000 |                   440 |     19 630 |        2.04
     5 |       76 500 |      2 200 |   2.88 |           15 300 |                   440 |     20 110 |        1.99
     6 |       88 000 |      2 620 |   2.98 |           14 667 |                   437 |     19 900 |        2.01
     7 |       99 000 |      3 020 |   3.05 |           14 143 |                   431 |     20 050 |        1.97
     8 |      109 500 |      3 400 |   3.11 |           13 688 |                   425 |     20 200 |        2.00

 → plan na 4 tygodnie: Użytkownicy w tygodniu = 16 000, Konwertujący = 440.
   Kalkulator (MDE +15%): 26 466 na wariant, 3,31 tyg. → 4 tygodnie — zgodne
   z wierszem, więc koniec. Gdyby wyszło 6 tygodni, przelicz z wiersza 6.
   week_users ~20 000 i week_cr_pct ~2% co tydzień: tygodnie są podobne.
*/
