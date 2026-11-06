/*
 01 · PRZED TESTEM → kalkulator „Przed testem A/B”
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/
 Test karty produktu: wejście = view_item, konwersja = purchase.
 Tabelę `twoj-projekt.analytics_123456789.events_*` podmień w obu miejscach.
*/

-- poniedziałek: początek pełnych tygodni PRZED testem (bez bieżącego tygodnia);
-- przykład: 5 tygodni 2026-08-03 – 2026-09-06 przed testem startującym 2026-09-07;
-- okno może obejmować test A/A (ab1 od 2026-08-24): obie grupy widzą obecną stronę
DECLARE window_start DATE DEFAULT DATE '2026-08-03';
DECLARE max_weeks INT64 DEFAULT 5;  -- najwyżej 8: tyle co limit w kalkulatorze
DECLARE test_start DATE DEFAULT DATE '2026-09-07';  -- pierwszy dzień testu

-- ASSERT przerywa skrypt z komunikatem, gdy warunek = FALSE;
-- DAYOFWEEK w BigQuery liczy od niedzieli: 1 = niedziela, 2 = poniedziałek
ASSERT EXTRACT(DAYOFWEEK FROM window_start) = 2
  AS 'window_start musi być poniedziałkiem';
ASSERT max_weeks BETWEEN 1 AND 8
  AS 'max_weeks: od 1 do 8 tygodni';
-- pierwszy dzień PO oknie (start + max_weeks × 7) musi wypaść najpóźniej w dniu startu testu
ASSERT DATE_ADD(window_start, INTERVAL max_weeks * 7 DAY) <= test_start
  AS 'okno sięga w okres testu: przesuń window_start wstecz albo zmniejsz max_weeks';
-- brak dziennej tabeli (przerwa w eksporcie) zaniża wynik po cichu
ASSERT (
  SELECT COUNT(DISTINCT _TABLE_SUFFIX)
  FROM `twoj-projekt.analytics_123456789.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', window_start)
    AND FORMAT_DATE('%Y%m%d', DATE_ADD(window_start, INTERVAL max_weeks * 7 - 1 DAY))
) = max_weeks * 7
  AS 'brakuje dziennych tabel eksportu w oknie';

WITH events AS (
  -- _TABLE_SUFFIX ogranicza skanowane dni, czyli koszt zapytania;
  -- events_* to osobna tabela na każdy dzień, a _TABLE_SUFFIX to końcówka jej nazwy
  -- ('20260803') — porównanie tekstów działa, bo format ma stałą długość
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    ecommerce.transaction_id AS transaction_id,
    ecommerce.purchase_revenue AS revenue,
    -- numer tygodnia w oknie: event_date to tekst 'YYYYMMDD' (stąd PARSE_DATE),
    -- DATE_DIFF daje dni od window_start, DIV dzieli całkowicie (ucina resztę),
    -- +1 numeruje od 1: dni 0–6 → tydzień 1, dni 7–13 → tydzień 2
    DIV(DATE_DIFF(PARSE_DATE('%Y%m%d', event_date), window_start, DAY), 7) + 1
      AS week_no
  FROM `twoj-projekt.analytics_123456789.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', window_start)
      AND FORMAT_DATE(
        '%Y%m%d',
        -- − 1, bo BETWEEN obejmuje oba końce: 5 tygodni = 35 dni = start + 34
        DATE_ADD(window_start, INTERVAL max_weeks * 7 - 1 DAY)
      )
    AND event_name IN ('view_item', 'purchase')
    -- Consent Mode bez zgody wysyła eventy bez user_pseudo_id — bez filtra
    -- GROUP BY skleiłby ich wszystkich w jednego użytkownika
    AND user_pseudo_id IS NOT NULL
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

user_purchases AS (
  -- zamówienia PO pierwszym wejściu, każde raz: odświeżona strona podziękowania
  -- wysyła ten sam transaction_id ponownie; zakup bez niego liczy się raz na event
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
  -- okno k tygodni: weszli w tygodniach 1..k, kupili do końca tygodnia k;
  -- GENERATE_ARRAY(1, max_weeks) = [1, 2, …, max_weeks], UNNEST robi z tablicy
  -- wiersze w; JOIN łączy każdego użytkownika z każdym oknem, w którym już był,
  -- więc jeden przebieg liczy wszystkie długości okna naraz
  SELECT
    w AS weeks,
    f.user_pseudo_id,
    -- bez zakupu w oknie LOGICAL_OR daje NULL albo FALSE — osoba nie jest konwertującą
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
  -- przychód osoby przycięty do 99,9 percentyla przychodu kupujących w oknie, jak
  -- w wyniku testu; średnia i odchylenie po wszystkich osobach, razem z zerami
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

/*
 ─── WYNIK ────────────────────────────────────────────────────────────────
 weeks               → planowana długość testu w tygodniach
 users_per_week      → kalkulator: Użytkownicy w tygodniu
 converters_per_week → kalkulator: Konwertujący w tygodniu
 revenue_per_user    → kalkulator (Przychód na użytkownika): Przychód na użytkownika
 revenue_sd          → kalkulator (Przychód na użytkownika): Odchylenie przychodu na użytkownika
 revenue_per_user i revenue_sd dotyczą całego okna, nie tygodnia — tak jak
 przychód osoby w wyniku testu, który liczy się do końca testu.
 users i converters to osoby (user_pseudo_id), nie sesje ani zamówienia;
 CR liczy kalkulator, nie zapytanie.

 Jak użyć: wpisz wiersz z liczbą tygodni, którą planujesz. Kalkulator
 policzył inny czas testu? Weź wiersz z tym czasem i przelicz jeszcze raz —
 koniec, gdy czas z kalkulatora zgadza się z wierszem.

 Dlaczego okna, a nie jeden tydzień: każdy użytkownik liczy się raz, od
 pierwszego wejścia, z zakupem do końca okna — tak jak w wyniku testu.
 Ludzie wracają, więc w dłuższym oknie jest mniej unikalnych na tydzień
 (test zbiera ich wolniej), a CR jest wyższy (więcej czasu na zakup).

 Przykład (liczby poglądowe):
 weeks | users_per_week | converters_per_week | revenue_per_user | revenue_sd
 ------+----------------+---------------------+------------------+-----------
     1 |         25 000 |                 375 |             4.50 |      41.00
     2 |         22 500 |                 383 |             5.10 |      43.50
     3 |         21 000 |                 392 |             5.60 |      45.20
     4 |         20 000 |                 400 |             6.00 |      46.50
     5 |         19 200 |                 403 |             6.30 |      47.40

 → plan 5 tygodni: 19 200 / 403 → kalkulator (MDE +15%) liczy 4 tygodnie
   → wiersz 4: 20 000 / 400 → kalkulator liczy 4 tygodnie. Zgodne, koniec.
*/
SELECT
  weeks,
  -- „/” na liczbach całkowitych daje FLOAT64; ROUND zaokrągla, CAST wraca do INT64
  CAST(ROUND(users_unique / weeks) AS INT64) AS users_per_week,
  CAST(ROUND(converters / weeks) AS INT64) AS converters_per_week,
  ROUND(revenue_per_user, 2) AS revenue_per_user,
  ROUND(revenue_sd, 2) AS revenue_sd
FROM windows
ORDER BY weeks;
