/*
 01 · PRZED TESTEM → kalkulator „Przed testem A/B”
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/
 Test karty produktu: wejście = view_item, konwersja = purchase.
*/

-- poniedziałek: początek pełnych tygodni PRZED testem (bez bieżącego tygodnia);
-- domyślnie 5 tygodni 2020-11-02 – 2020-12-06, bo przykładowy test startuje 2020-12-07
DECLARE window_start DATE DEFAULT DATE '2020-11-02';
DECLARE max_weeks INT64 DEFAULT 5;  -- najwyżej 8: tyle co limit w kalkulatorze
DECLARE test_start DATE DEFAULT DATE '2020-12-07';  -- pierwszy dzień testu

-- ASSERT przerywa skrypt z komunikatem, gdy warunek = FALSE;
-- DAYOFWEEK w BigQuery liczy od niedzieli: 1 = niedziela, 2 = poniedziałek
ASSERT EXTRACT(DAYOFWEEK FROM window_start) = 2
  AS 'window_start musi być poniedziałkiem';
ASSERT max_weeks BETWEEN 1 AND 8
  AS 'max_weeks: od 1 do 8 tygodni';
-- pierwszy dzień PO oknie (start + max_weeks × 7) musi wypaść najpóźniej w dniu startu testu
ASSERT DATE_ADD(window_start, INTERVAL max_weeks * 7 DAY) <= test_start
  AS 'okno sięga w okres testu: przesuń window_start wstecz albo zmniejsz max_weeks';

WITH events AS (
  -- _TABLE_SUFFIX ogranicza skanowane dni, czyli koszt zapytania;
  -- events_* to osobna tabela na każdy dzień, a _TABLE_SUFFIX to końcówka jej nazwy
  -- ('20201102') — porównanie tekstów działa, bo format ma stałą długość
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    -- numer tygodnia w oknie: event_date to tekst 'YYYYMMDD' (stąd PARSE_DATE),
    -- DATE_DIFF daje dni od window_start, DIV dzieli całkowicie (ucina resztę),
    -- +1 numeruje od 1: dni 0–6 → tydzień 1, dni 7–13 → tydzień 2
    DIV(DATE_DIFF(PARSE_DATE('%Y%m%d', event_date), window_start, DAY), 7) + 1
      AS week_no
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', window_start)
      AND FORMAT_DATE(
        '%Y%m%d',
        -- − 1, bo BETWEEN obejmuje oba końce: 5 tygodni = 35 dni = start + 34
        DATE_ADD(window_start, INTERVAL max_weeks * 7 - 1 DAY)
      )
    AND event_name IN ('view_item', 'purchase')
),

first_view AS (
  -- pierwsze wejście na kartę produktu: moment i numer tygodnia
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

windows AS (
  -- okno k tygodni: weszli w tygodniach 1..k, kupili do końca tygodnia k
  SELECT
    w AS weeks,
    -- COUNTIF liczy wiersze z warunkiem TRUE; bez zakupu purchase_week jest NULL,
    -- warunek daje NULL, więc taki użytkownik nie trafia do converters
    COUNTIF(f.first_week <= w) AS users_unique,
    COUNTIF(f.first_week <= w AND fp.purchase_week <= w) AS converters
  -- GENERATE_ARRAY(1, max_weeks) = [1, 2, …, max_weeks], UNNEST robi z tablicy
  -- wiersze w; CROSS JOIN łączy każdego użytkownika z każdym oknem, więc jeden
  -- przebieg liczy wszystkie długości okna naraz
  FROM UNNEST(GENERATE_ARRAY(1, max_weeks)) AS w
  CROSS JOIN first_view AS f
  LEFT JOIN first_purchase AS fp
    ON fp.user_pseudo_id = f.user_pseudo_id
  GROUP BY w
)

/*
 ─── WYNIK ────────────────────────────────────────────────────────────────
 weeks               → planowana długość testu w tygodniach
 users_per_week      → kalkulator: Użytkownicy w tygodniu
 converters_per_week → kalkulator: Konwertujący w tygodniu

 Jak użyć: wpisz wiersz z liczbą tygodni, którą planujesz. Kalkulator
 policzył inny czas testu? Weź wiersz z tym czasem i przelicz jeszcze raz —
 koniec, gdy czas z kalkulatora zgadza się z wierszem.

 Dlaczego okna, a nie jeden tydzień: każdy użytkownik liczy się raz, od
 pierwszego wejścia, z zakupem do końca okna — tak jak w wyniku testu.
 Ludzie wracają, więc w dłuższym oknie jest mniej unikalnych na tydzień
 (test zbiera ich wolniej), a CR jest wyższy (więcej czasu na zakup).

 Przykład (liczby poglądowe):
 weeks | users_per_week | converters_per_week
 ------+----------------+--------------------
     1 |         25 000 |                 375
     2 |         22 500 |                 383
     3 |         21 000 |                 392
     4 |         20 000 |                 400
     5 |         19 200 |                 403

 → plan 5 tygodni: 19 200 / 403 → kalkulator (MDE +15%) liczy 4 tygodnie
   → wiersz 4: 20 000 / 400 → kalkulator liczy 4 tygodnie. Zgodne, koniec.
*/
SELECT
  weeks,
  -- „/” na liczbach całkowitych daje FLOAT64; ROUND zaokrągla, CAST wraca do INT64
  CAST(ROUND(users_unique / weeks) AS INT64) AS users_per_week,
  CAST(ROUND(converters / weeks) AS INT64) AS converters_per_week
FROM windows
ORDER BY weeks;
