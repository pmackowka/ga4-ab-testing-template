/*
================================================================================
 03 · PO TEŚCIE — kalkulator „Po teście A/B”
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/
================================================================================

 SCENARIUSZ: test karty produktu. Wejście do testu = pierwsze przypisanie do
 wariantu na karcie produktu, konwersja = purchase.

 Przypisanie do wariantu: GA4 dla zewnętrznych narzędzi A/B zaleca zdarzenie
 experience_impression z parametrem exp_variant_string w formacie
 NARZĘDZIE-TEST-WARIANT, np. „abt-pdp_redesign-B”
 (developers.google.com/analytics/devguides/collection/ga4/integration).
 Identyfikatory bez myślników w środku — myślnik rozdziela części.
 Jeśli Twoje narzędzie zapisuje wariant inaczej, zmień tylko CTE assignments.

 CO LICZY: dla każdego wariantu — ilu unikalnych użytkowników trafiło do testu
 i ilu z nich kupiło PO pierwszym przypisaniu. Wyklucza ludzi przypisanych do
 więcej niż jednego wariantu.

 ─── Pola kalkulatora z tego zapytania ──────────────────────────────────────

 Użytkownicy A (kontrola) / Użytkownicy B (wariant)   ← users
   Unikalni użytkownicy liczeni od pierwszego przypisania w okresie testu.
 Konwertujący A / Konwertujący B                      ← converters
   Kupujący PO pierwszym przypisaniu; osoby, nie zamówienia. Zakup sprzed
   przypisania nie mógł zależeć od wariantu.
 Wiersz „A (kontrola)” wpisujesz jako A, drugi jako B. Przy 3+ wariantach
 oceniasz każdą parę z kontrolą osobno.

 Pozostałe pola:
   Liczba wariantów, Poziom ufności, Rodzaj testu  ← te same co w planie (01);
     zmiana po zobaczeniu wyniku to naginanie wyniku
   Dane z planu (użytkownicy na wariant, MDE)      ← kalkulator Przed testem;
     kalkulator sprawdzi, czy test nie zatrzymano za wcześnie albo nie
     przedłużano „aż wyjdzie”
   Miesięczny przychód ze strony testowej          ← zapytanie 04

 ─── Kontrola jakości w wyniku ──────────────────────────────────────────────

 users_in_many_variants — przypisani do 2+ wariantów (wyczyszczone cookies,
   błąd w tagu). Wykluczeni, bo nie wiadomo, co widzieli. Powyżej ~1%
   użytkowników — szukaj błędu w przypisaniu, zanim zaufasz wynikowi.

 ─── Jak czytać wynik w kalkulatorze ────────────────────────────────────────

 p-value
   Prawdopodobieństwo takiego lub bardziej skrajnego wyniku, gdyby wzrostu nie
   było (H0). Istotny, gdy p-value < α (zwykle 0,05). To NIE jest
   prawdopodobieństwo, że wariant jest lepszy — „na 95% to zasługa zmiany”
   jest błędem.

 Zakres możliwego wzrostu (przedział ufności)
   Wzrosty zgodne z danymi. Obejmuje zero = nie da się odróżnić wzrostu od
   przypadku. Ważniejszy niż werdykt: wyniki „istotny” i „nieistotny” mogą mieć
   prawie ten sam zakres.

 Podział użytkowników A/B (SRM, sample ratio mismatch)
   Przy podziale 50/50 grupy powinny być prawie równe. Test χ² z p-value
   < 0,001 = test zepsuty (losowanie, przekierowania, zbieranie danych) —
   wyniku nie interpretujesz.

 Winner's curse
   Istotny wynik przy wzroście mniejszym niż MDE z planu: test miał przy takim
   wzroście słabą moc, a istotne wyniki takich testów zawyżają wzrost.

 Analizuj raz
   Każde zerknięcie w trakcie z możliwością zatrzymania podnosi ryzyko
   fałszywego pozytywu ponad α. Wynik czytasz raz, po zebraniu zaplanowanej
   liczby użytkowników.

 ─── Tryb demo ──────────────────────────────────────────────────────────────

 Publiczny przykładowy eksport GA4 nie ma testu A/B. Przy demo_mode = TRUE
 każdy z view_item dostaje wariant A albo B z hasha user_pseudo_id (stały
 podział 50/50). Na własnych danych: demo_mode = FALSE i nazwa testu w test_id.
================================================================================
*/

-- TRUE = przykładowe dane bez testu (wariant z hasha), FALSE = Twój test
DECLARE demo_mode BOOL DEFAULT TRUE;
-- okres testu: pełne tygodnie, od pierwszego do ostatniego dnia
DECLARE test_start DATE DEFAULT DATE '2020-12-07';
DECLARE test_end DATE DEFAULT DATE '2021-01-03';
-- środkowa część exp_variant_string („abt-pdp_redesign-B” → pdp_redesign)
DECLARE test_id STRING DEFAULT 'pdp_redesign';
-- wariant kontrolny
DECLARE control_variant STRING DEFAULT 'A';

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    (
      SELECT value.string_value
      FROM UNNEST(event_params)
      WHERE key = 'exp_variant_string'
    ) AS exp_variant_string
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', test_start)
      AND FORMAT_DATE('%Y%m%d', test_end)
    AND event_name IN ('experience_impression', 'view_item', 'purchase')
),

assignments AS (
  -- każde przypisanie: kto, kiedy, który wariant
  SELECT
    user_pseudo_id,
    event_timestamp,
    IF(
      demo_mode,
      -- demo: stały podział 50/50 z hasha identyfikatora
      IF(MOD(ABS(FARM_FINGERPRINT(user_pseudo_id)), 2) = 0, 'A', 'B'),
      -- Twój test: trzecia część NARZĘDZIE-TEST-WARIANT
      SPLIT(exp_variant_string, '-')[SAFE_OFFSET(2)]
    ) AS variant
  FROM events
  WHERE
    IF(
      demo_mode,
      event_name = 'view_item',
      event_name = 'experience_impression'
        AND SPLIT(exp_variant_string, '-')[SAFE_OFFSET(1)] = test_id
    )
),

users_assigned AS (
  -- jeden wiersz na użytkownika: pierwsze przypisanie i liczba wariantów
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_assignment_ts,
    ANY_VALUE(variant) AS variant,
    COUNT(DISTINCT variant) AS variants_seen
  FROM assignments
  WHERE variant IS NOT NULL
  GROUP BY user_pseudo_id
),

clean_users AS (
  -- tylko ludzie z jednym wariantem
  SELECT user_pseudo_id, first_assignment_ts, variant
  FROM users_assigned
  WHERE variants_seen = 1
),

converters AS (
  -- zakup PO pierwszym przypisaniu, w okresie testu; DISTINCT = osoby
  SELECT DISTINCT u.user_pseudo_id
  FROM clean_users AS u
  JOIN events AS p
    ON p.user_pseudo_id = u.user_pseudo_id
    AND p.event_name = 'purchase'
    AND p.event_timestamp > u.first_assignment_ts
)

SELECT
  IF(
    u.variant = control_variant,
    'A (kontrola)',
    CONCAT('B (wariant ', u.variant, ')')
  ) AS calculator_field,
  COUNT(*) AS users,
  COUNT(c.user_pseudo_id) AS converters,
  ROUND(SAFE_DIVIDE(COUNT(c.user_pseudo_id), COUNT(*)) * 100, 4) AS cr_pct,
  -- ta sama liczba w każdym wierszu: wykluczeni za 2+ warianty
  (SELECT COUNTIF(variants_seen > 1) FROM users_assigned) AS users_in_many_variants
FROM clean_users AS u
LEFT JOIN converters AS c
  USING (user_pseudo_id)
GROUP BY u.variant
ORDER BY u.variant = control_variant DESC, u.variant;
