/*
================================================================================
 03 · PO TEŚCIE — dane do kalkulatora „Po teście A/B”
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/
================================================================================

 Co liczy: dla każdego wariantu — ilu unikalnych użytkowników trafiło do testu
 i ilu z nich wykonało konwersję PO przypisaniu do wariantu. Dodatkowo pokazuje
 użytkowników, którzy trafili do więcej niż jednego wariantu (i ich wyklucza).

 ─── Pola kalkulatora, które wypełnia to zapytanie ───────────────────────────

 „Użytkownicy A (kontrola)”, „Użytkownicy B (wariant)”   ← kolumna users
   Unikalni użytkownicy przypisani do wariantu, nie sesje. Liczeni od
   PIERWSZEGO przypisania w okresie testu.

 „Konwertujący A”, „Konwertujący B”                       ← kolumna converters
   Użytkownicy, którzy wykonali konwersję po wejściu do testu; osoby, nie
   konwersje. Konwersja sprzed przypisania nie mogła zależeć od wariantu,
   więc jej nie liczymy.

 Wiersz z control_variant (domyślnie 'A') wpisujesz jako A, drugi jako B.
 Przy więcej niż dwóch wariantach oceniasz każdą parę z kontrolą osobno
 i wpisujesz w kalkulatorze „Liczba wariantów razem z kontrolą” (korekta
 Bonferroniego — opis w README.md).

 ─── Pola, które bierzesz z innych miejsc ───────────────────────────────────

 „Dane z planu testu” (użytkownicy na wariant, MDE)  ← z kalkulatora Przed testem
 „Miesięczny przychód ze strony testowej”            ← zapytanie 04
 „Poziom ufności”, „Rodzaj testu”                    ← te same co w planie

 ─── Kontrola jakości w wyniku ──────────────────────────────────────────────

 users_in_many_variants — ludzie z przypisaniem do 2+ wariantów (np. po
 wyczyszczeniu cookies albo przez błąd w tagu). Zapytanie ich wyklucza, bo nie
 wiadomo, który wariant widzieli. Jeśli to więcej niż ~1% użytkowników, szukaj
 błędu w przypisaniu, zanim zaufasz wynikowi. Nierówny podział A/B (SRM)
 sprawdzi sam kalkulator.

 ─── Tryb demo ──────────────────────────────────────────────────────────────

 Publiczny przykładowy eksport GA4 nie ma żadnego testu A/B. Przy
 demo_mode = TRUE zapytanie udaje test: każdy, kto wszedł na kartę produktu,
 dostaje wariant A albo B z hasha user_pseudo_id (stały podział 50/50).
 Na własnych danych ustaw demo_mode = FALSE — wtedy wariant pochodzi ze
 zdarzenia przypisania (domyślnie `ab_assign` z parametrami `ab_test` i
 `ab_variant`, jak w teście ustawianym przez GTM na first-party cookie:
 https://pmdata.pl/artykuly/wlasne-testy-ab-gtm-firebase/).
================================================================================
*/

-- ─── Parametry ────────────────────────────────────────────────────────────────

-- TRUE = przykładowe dane bez testu (wariant z hasha), FALSE = Twój test
DECLARE demo_mode BOOL DEFAULT TRUE;
-- okres testu: od pierwszego do ostatniego dnia, pełne tygodnie
DECLARE test_start DATE DEFAULT DATE '2020-12-07';
DECLARE test_end DATE DEFAULT DATE '2021-01-03';
-- zdarzenie przypisania do wariantu i jego parametry (gdy demo_mode = FALSE)
DECLARE assignment_event STRING DEFAULT 'ab_assign';
DECLARE test_name STRING DEFAULT 'pdp_redesign';
-- w trybie demo: zdarzenie, które „wpuszcza” do testu
DECLARE demo_exposure_event STRING DEFAULT 'view_item';
DECLARE conversion_event STRING DEFAULT 'purchase';
-- nazwa wariantu kontrolnego (w GTM często 'v0')
DECLARE control_variant STRING DEFAULT 'A';

-- ─── Zapytanie ────────────────────────────────────────────────────────────────

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    event_params
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', test_start)
      AND FORMAT_DATE('%Y%m%d', test_end)
    AND event_name IN (assignment_event, demo_exposure_event, conversion_event)
),

assignments AS (
  -- każde zdarzenie przypisania: kto, kiedy, do którego wariantu
  SELECT
    user_pseudo_id,
    event_timestamp,
    IF(
      demo_mode,
      -- demo: stały podział 50/50 z hasha identyfikatora
      IF(MOD(ABS(FARM_FINGERPRINT(user_pseudo_id)), 2) = 0, 'A', 'B'),
      -- Twój test: wariant z parametru zdarzenia
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_variant')
    ) AS variant
  FROM events
  WHERE
    IF(
      demo_mode,
      event_name = demo_exposure_event,
      event_name = assignment_event
        AND (
          SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test'
        ) = test_name
    )
),

users_assigned AS (
  -- jeden wiersz na użytkownika: pierwsze przypisanie i liczba różnych wariantów
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
  -- tylko ludzie z jednym wariantem — u pozostałych nie wiadomo, co widzieli
  SELECT user_pseudo_id, first_assignment_ts, variant
  FROM users_assigned
  WHERE variants_seen = 1
),

converters AS (
  -- konwersja PO pierwszym przypisaniu, w okresie testu; DISTINCT = osoby
  SELECT DISTINCT u.user_pseudo_id
  FROM clean_users AS u
  JOIN events AS c
    ON c.user_pseudo_id = u.user_pseudo_id
    AND c.event_name = conversion_event
    AND c.event_timestamp > u.first_assignment_ts
)

SELECT
  IF(u.variant = control_variant, 'A (kontrola)', CONCAT('B (wariant ', u.variant, ')'))
    AS calculator_field,
  u.variant,
  COUNT(*) AS users,
  COUNT(c.user_pseudo_id) AS converters,
  ROUND(SAFE_DIVIDE(COUNT(c.user_pseudo_id), COUNT(*)) * 100, 4) AS cr_pct,
  -- ten sam licznik w każdym wierszu: ilu wykluczono za wiele wariantów
  (SELECT COUNTIF(variants_seen > 1) FROM users_assigned) AS users_in_many_variants
FROM clean_users AS u
LEFT JOIN converters AS c
  USING (user_pseudo_id)
GROUP BY u.variant
ORDER BY u.variant = control_variant DESC, u.variant;
