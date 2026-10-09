/*
================================================================================
 01 · PRZED TESTEM — dane do kalkulatora „Przed testem A/B”
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/
================================================================================

 Co liczy: dla kilku pełnych tygodni przed testem — ilu unikalnych użytkowników
 weszło na stronę, którą chcesz testować, i ilu z nich wykonało konwersję PO tym
 wejściu. Na końcu wiersz ze średnią — to ją wpisujesz do kalkulatora.

 ─── Pola kalkulatora, które wypełnia to zapytanie ───────────────────────────

 „Użytkownicy w tygodniu”                     ← kolumna users_weekly (wiersz ŚREDNIA)
   Unikalni użytkownicy, którzy w tygodniu weszli na stronę objętą testem
   (np. kartę produktu), łącznie dla wszystkich wariantów; nie sesje.
   Dlaczego użytkownicy, a nie sesje: narzędzie do testów losuje LUDZI
   (cookie), a jedna osoba robi wiele sesji. Sesje tej samej osoby nie są
   niezależne, więc liczone osobno zaniżają błąd standardowy i dają fałszywe
   pozytywy.

 „Konwertujący w tygodniu”                    ← kolumna converters_weekly (wiersz ŚREDNIA)
   Ilu z tych użytkowników wykonało konwersję (zakup, telefon, formularz) po
   wejściu na stronę testową; liczysz osoby, nie konwersje.
   Dlaczego „po wejściu”: konwersja sprzed wejścia na stronę testową nie mogła
   zależeć od wariantu, więc w teście też nie będzie się liczyć.
   Dlaczego osoby, nie zamówienia: kalkulator porównuje odsetek ludzi, którzy
   konwertowali (CR). Ktoś z trzema zamówieniami to jeden konwertujący.

 Kalkulator sam policzy z tych dwóch liczb CR (conversion rate):
   CR = konwertujący / użytkownicy        ← kolumna cr_pct, tylko do kontroli

 ─── Pola kalkulatora, których NIE da się policzyć z danych ──────────────────

 Te ustawiasz sam — opis każdego w README.md, sekcja „Słownik”:
   Najmniejszy wzrost do wykrycia (MDE, %), Liczba wariantów razem z kontrolą,
   Poziom ufności, Moc testu, Rodzaj testu, Najdłużej możesz testować.

 ─── Dlaczego kilka tygodni, a nie jeden ────────────────────────────────────

 Jeden tydzień może być nietypowy (promocja, święto, awaria). Kilka pełnych
 tygodni pokazuje, jak bardzo liczby się wahają. Jeśli tygodnie różnią się
 mocno, nie bierz średniej w ciemno — sprawdź, skąd ta różnica.

 ─── Ograniczenia ────────────────────────────────────────────────────────────

 • user_pseudo_id to przeglądarka, nie człowiek: telefon i laptop tej samej
   osoby to dwóch użytkowników. Narzędzie do testów losuje tak samo, więc plan
   i wynik zostają spójne.
 • Konwersja liczona w obrębie tego samego tygodnia co wejście. Ktoś, kto wszedł
   w niedzielę i kupił w poniedziałek, nie jest tu konwertującym.
 • Na dłuższy test patrz zapytanie 02 — unikalnych użytkowników w 4 tygodniach
   jest mniej niż 4 × tydzień.

 Domyślnie zapytanie działa na publicznym przykładowym eksporcie GA4 (sklep
 Google Merchandise Store, 2020-11-01 – 2021-01-31), więc uruchomisz je bez
 własnych danych. Na swoich danych podmień nazwę tabeli w CTE `events`.
================================================================================
*/

-- ─── Parametry ────────────────────────────────────────────────────────────────

-- poniedziałek, od którego liczymy pełne tygodnie
DECLARE first_week_start DATE DEFAULT DATE '2020-11-02';
-- ile pełnych tygodni wstecz (zalecane: 4)
DECLARE weeks_count INT64 DEFAULT 4;
-- zdarzenie = wejście na stronę objętą testem (tu: karta produktu)
DECLARE exposure_event STRING DEFAULT 'view_item';
-- zdarzenie = konwersja, którą mierzysz w teście
DECLARE conversion_event STRING DEFAULT 'purchase';

-- tydzień liczymy od poniedziałku do niedzieli — inaczej tygodnie się przesuną
ASSERT EXTRACT(DAYOFWEEK FROM first_week_start) = 2
  AS 'first_week_start musi być poniedziałkiem';

-- ─── Zapytanie ────────────────────────────────────────────────────────────────

WITH events AS (
  -- tylko dwa potrzebne zdarzenia i tylko z wybranych tygodni;
  -- filtr _TABLE_SUFFIX ogranicza skanowane dane (i koszt)
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    DATE_TRUNC(PARSE_DATE('%Y%m%d', event_date), WEEK(MONDAY)) AS week_start
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', first_week_start)
      AND FORMAT_DATE(
        '%Y%m%d',
        DATE_ADD(first_week_start, INTERVAL weeks_count * 7 - 1 DAY)
      )
    AND event_name IN (exposure_event, conversion_event)
),

exposed AS (
  -- „Użytkownicy w tygodniu”: każdy użytkownik raz na tydzień,
  -- z momentem PIERWSZEGO wejścia na stronę testową w tym tygodniu
  SELECT
    week_start,
    user_pseudo_id,
    MIN(event_timestamp) AS first_exposure_ts
  FROM events
  WHERE event_name = exposure_event
  GROUP BY week_start, user_pseudo_id
),

converted AS (
  -- „Konwertujący w tygodniu”: ci z `exposed`, którzy mieli konwersję
  -- PO pierwszym wejściu, w tym samym tygodniu; DISTINCT = osoby, nie zamówienia
  SELECT DISTINCT
    e.week_start,
    e.user_pseudo_id
  FROM exposed AS e
  JOIN events AS c
    ON c.user_pseudo_id = e.user_pseudo_id
    AND c.week_start = e.week_start
    AND c.event_name = conversion_event
    AND c.event_timestamp > e.first_exposure_ts
),

per_week AS (
  SELECT
    e.week_start,
    COUNT(*) AS users_weekly,
    COUNT(c.user_pseudo_id) AS converters_weekly
  FROM exposed AS e
  LEFT JOIN converted AS c
    USING (week_start, user_pseudo_id)
  GROUP BY e.week_start
)

-- wiersze tygodni — do sprawdzenia, czy tygodnie są podobne
SELECT
  CAST(week_start AS STRING) AS week,
  users_weekly,
  converters_weekly,
  ROUND(SAFE_DIVIDE(converters_weekly, users_weekly) * 100, 2) AS cr_pct
FROM per_week

UNION ALL

-- wiersz do wpisania w kalkulator
SELECT
  'ŚREDNIA → wpisz do kalkulatora' AS week,
  CAST(ROUND(AVG(users_weekly)) AS INT64) AS users_weekly,
  CAST(ROUND(AVG(converters_weekly)) AS INT64) AS converters_weekly,
  ROUND(SAFE_DIVIDE(SUM(converters_weekly), SUM(users_weekly)) * 100, 2) AS cr_pct
FROM per_week

ORDER BY week;
