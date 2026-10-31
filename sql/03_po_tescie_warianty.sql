/*
 03 · PO TEŚCIE → kalkulator „Po teście A/B”
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/
 Liczy test z gtm/01_dwa_warianty.html (klucz ab1, v0/v1 po 50%): wariant
 losuje tag w przeglądarce i zapisuje w first-party cookie, SQL tylko go czyta
 (https://pmdata.pl/artykuly/wlasne-testy-ab-gtm-firebase/). Inne tagi z gtm/:
 zmień test_name i variants ('out' z 03/04 nie trafia do danych). Wymaga
 konfiguracji z README, sekcja Skrypty GTM:
 - krok 2 (obowiązkowy): tag GA4 Event ab_assign z parametrami ab_test
   i ab_variant — z niego zapytanie wie, kto i kiedy wszedł do testu;
 - krok 3 (zalecany): ab_test i ab_variant także na view_item i purchase —
   bez nich excluded_mixed nie wyłapie ponownego losowania.
 Tabelę `twoj-projekt.analytics_123456789.events_*` podmień w obu miejscach.
*/

DECLARE test_start DATE DEFAULT DATE '2026-09-07';  -- poniedziałek publikacji tagu
DECLARE test_end DATE DEFAULT DATE '2026-10-04';    -- niedziela: ostatni dzień testu
DECLARE test_name STRING DEFAULT 'ab1';             -- = TEST w gtm/01_dwa_warianty.html
DECLARE control_variant STRING DEFAULT 'v0';        -- wersja dotychczasowa
DECLARE variants ARRAY<STRING> DEFAULT ['v0', 'v1'];  -- = VARIANTS w tagu; inna wartość w danych = błąd
DECLARE conversion_event STRING DEFAULT 'purchase';
-- punkt ekspozycji: user wchodzi do testu na pierwszym z tych eventów z wariantem;
-- tag z gtm/01 losuje na stronie testowej, więc ab_assign wystarcza, a view_item
-- łapie powracających, którzy mają ciasteczko sprzed utraty _ga
DECLARE exposure_events ARRAY<STRING> DEFAULT ['ab_assign', 'view_item'];

ASSERT EXTRACT(DAYOFWEEK FROM test_start) = 2
  AS 'test_start musi być poniedziałkiem';
ASSERT EXTRACT(DAYOFWEEK FROM test_end) = 1 AND test_end > test_start
  AS 'test_end musi być niedzielą po test_start: pełne tygodnie';
ASSERT control_variant IN UNNEST(variants)
  AS 'control_variant musi być na liście variants';
-- GA4 dopisuje zdarzenia do dziennej tabeli jeszcze do 72 h (spóźnione hity
-- z aplikacji, przetwarzanie) — wcześniejsze uruchomienie zaniża ostatnie dni
ASSERT test_end <= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)
  AS 'uruchom najwcześniej 3 dni po test_end: GA4 jeszcze dopisuje dane';
-- brak dziennej tabeli (przerwa w eksporcie, limit) zaniża wynik po cichu;
-- zapytanie czyta tylko pseudokolumnę _TABLE_SUFFIX, bez kolumn z danymi
ASSERT (
  SELECT COUNT(DISTINCT _TABLE_SUFFIX)
  FROM `twoj-projekt.analytics_123456789.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', test_start)
    AND FORMAT_DATE('%Y%m%d', test_end)
) = DATE_DIFF(test_end, test_start, DAY) + 1
  AS 'brakuje dziennych tabel eksportu w okresie testu';

WITH events AS (
  -- bez filtra na event_name: koszt zależy od kolumn, nie wierszy, a wariant
  -- z każdego eventu wyłapuje ponowne losowanie
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test')
      AS ab_test,
    (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_variant')
      AS ab_variant
  FROM `twoj-projekt.analytics_123456789.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', test_start)
      AND FORMAT_DATE('%Y%m%d', test_end)
    -- Consent Mode bez zgody na analytics_storage wysyła eventy bez
    -- user_pseudo_id; bez tego filtra wszyscy tacy userzy zlewają się
    -- w jednego (GROUP BY NULL) z wariantem i zakupami wielu osób
    AND user_pseudo_id IS NOT NULL
),

users_assigned AS (
  -- jeden wiersz na eksponowanego użytkownika: pierwsza ekspozycja, jej wariant
  -- i liczba wariantów na wszystkich eventach testu (nowe losowanie = 2+)
  SELECT
    user_pseudo_id,
    MIN(IF(event_name IN UNNEST(exposure_events), event_timestamp, NULL))
      AS first_exposure_ts,
    ARRAY_AGG(
      IF(event_name IN UNNEST(exposure_events), ab_variant, NULL)
      IGNORE NULLS ORDER BY event_timestamp LIMIT 1
    )[SAFE_OFFSET(0)] AS variant,
    COUNT(DISTINCT ab_variant) AS variants_seen
  FROM events
  WHERE ab_test = test_name AND ab_variant IS NOT NULL
  GROUP BY user_pseudo_id
  HAVING first_exposure_ts IS NOT NULL
),

converters AS (
  -- konwersja PO pierwszej ekspozycji; DISTINCT = osoby, nie zamówienia, więc
  -- zdublowany purchase (odświeżona strona podziękowania) nie zawyża wyniku
  SELECT DISTINCT u.user_pseudo_id
  FROM users_assigned AS u
  JOIN events AS p
    ON p.user_pseudo_id = u.user_pseudo_id
    AND p.event_name = conversion_event
    AND p.event_timestamp > u.first_exposure_ts
)

/*
 ─── WYNIK ────────────────────────────────────────────────────────────────
 calculator_field → który wiersz kalkulatora: A (kontrola) albo B (wariant)
 users            → kalkulator: Użytkownicy A / Użytkownicy B
 converters       → kalkulator: Konwertujący A / Konwertujący B
 excluded_mixed   → do kalkulatora nie idzie: kontrola jakości danych

 users: unikalni użytkownicy od pierwszej ekspozycji w okresie testu.
 converters: ci z nich, którzy kupili PO pierwszej ekspozycji; osoby, nie
 zamówienia. Zapytanie przerywa się błędem, gdy brakuje kontroli albo
 wariantu albo w danych jest wariant spoza listy variants (tag z innymi
 wartościami albo literówka w zmiennej GTM).

 excluded_mixed: użytkownicy z 2+ wariantami (variants_seen > 1), wyjęci
 z users i converters, bo nie wiadomo, któremu wariantowi przypisać ich
 zakup. Wiersz = wariant ich PIERWSZEJ ekspozycji. To ok. połowa ponownie
 wylosowanych — druga połowa trafiła przypadkiem w ten sam wariant i jest
 niewidoczna (variants_seen = 1).
 Jak czytać, przy podobnych users w wierszach: różnica excluded_mixed między
 wierszem wariantu a kontrolą większa niż 2 × √(suma obu) jest podejrzana.
 Przykład niżej: 410 − 398 = 12, próg 2 × √808 ≈ 57 → w normie.
 Podejrzana różnica ma dwie możliwe przyczyny:
 - błąd: tag losuje ponownie mimo ciasteczka albo zapisuje je tylko w jednym
   wariancie — napraw i powtórz test;
 - efekt wariantu: wariant zmienia, jak często ludzie wracają po tygodniu,
   więc częściej tracą ciasteczko — tag działa, ale z jednego wariantu
   wypadają akurat najbardziej zaangażowani i wynik jest obciążony.
 W obu przypadkach nie ufaj wynikowi bez wyjaśnienia różnicy.

 Przykład (liczby poglądowe, zgodne z domyślnymi danymi kalkulatora):
 calculator_field | users  | converters | excluded_mixed
 -----------------+--------+------------+---------------
 A (kontrola)     | 36 700 |        734 |            410
 B (wariant v1)   | 36 750 |        846 |            398

 → kalkulator: „Wdrażaj B”, p-value 0,0048, wzrost od +4,61% do +25,59%.
*/
SELECT
  CASE
    -- funkcje okna po GROUP BY widzą cały wynik: brak któregoś wariantu
    -- albo obcy wariant przerywa zapytanie, zamiast oddać niepełny wynik
    WHEN LOGICAL_OR(u.variant NOT IN UNNEST(variants)) OVER ()
      THEN ERROR('w danych jest wariant spoza listy variants — sprawdź tag i zmienną GTM')
    WHEN COUNT(*) OVER () < ARRAY_LENGTH(variants)
      THEN ERROR(FORMAT('w danych brakuje wariantu z listy %t', variants))
    WHEN u.variant = control_variant THEN 'A (kontrola)'
    ELSE CONCAT('B (wariant ', u.variant, ')')
  END AS calculator_field,
  COUNTIF(u.variants_seen = 1) AS users,
  COUNTIF(u.variants_seen = 1 AND c.user_pseudo_id IS NOT NULL) AS converters,
  COUNTIF(u.variants_seen > 1) AS excluded_mixed
FROM users_assigned AS u
LEFT JOIN converters AS c
  USING (user_pseudo_id)
GROUP BY u.variant
ORDER BY u.variant = control_variant DESC, u.variant;
