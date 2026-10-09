/*
 02 · PO TEŚCIE → kalkulator „Po teście A/B”
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/
 Wariant: zdarzenie GA4 experience_impression, parametr exp_variant_string
 w formacie NARZĘDZIE-TEST-WARIANT, np. „abt-pdp_redesign-B”:
 https://developers.google.com/analytics/devguides/collection/ga4/integration
*/

-- TRUE: przykładowy eksport GA4 nie ma testu, wariant z hasha user_pseudo_id;
-- na własnych danych ustaw FALSE
DECLARE demo_mode BOOL DEFAULT TRUE;
DECLARE test_start DATE DEFAULT DATE '2020-12-07';   -- pełne tygodnie testu
DECLARE test_end DATE DEFAULT DATE '2021-01-03';
DECLARE test_id STRING DEFAULT 'pdp_redesign';       -- środkowa część exp_variant_string
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
      IF(MOD(ABS(FARM_FINGERPRINT(user_pseudo_id)), 2) = 0, 'A', 'B'),
      SPLIT(exp_variant_string, '-')[SAFE_OFFSET(2)]  -- część WARIANT
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
  -- przypisani do 2+ wariantów wypadają: nie wiadomo, co widzieli
  SELECT user_pseudo_id, first_assignment_ts, variant
  FROM users_assigned
  WHERE variants_seen = 1
),

converters AS (
  -- zakup PO pierwszym przypisaniu; DISTINCT = osoby, nie zamówienia
  SELECT DISTINCT u.user_pseudo_id
  FROM clean_users AS u
  JOIN events AS p
    ON p.user_pseudo_id = u.user_pseudo_id
    AND p.event_name = 'purchase'
    AND p.event_timestamp > u.first_assignment_ts
)

/*
 ─── WYNIK ────────────────────────────────────────────────────────────────
 calculator_field → który wiersz kalkulatora: A (kontrola) albo B (wariant)
 users            → kalkulator: Użytkownicy A / Użytkownicy B
 converters       → kalkulator: Konwertujący A / Konwertujący B

 users: unikalni użytkownicy od pierwszego przypisania w okresie testu.
 converters: ci z nich, którzy kupili PO pierwszym przypisaniu; osoby, nie
 zamówienia. Przypisani do 2+ wariantów są wykluczeni (nie wiadomo, co widzieli).

 Przykład (liczby poglądowe, zgodne z domyślnymi danymi kalkulatora):
 calculator_field | users  | converters
 -----------------+--------+-----------
 A (kontrola)     | 36 700 |        734
 B (wariant B)    | 36 750 |        846

 → kalkulator: „Wdrażaj B”, p-value 0,0048, wzrost od +4,61% do +25,59%.
*/
SELECT
  IF(
    u.variant = control_variant,
    'A (kontrola)',
    CONCAT('B (wariant ', u.variant, ')')
  ) AS calculator_field,
  COUNT(*) AS users,
  COUNT(c.user_pseudo_id) AS converters
FROM clean_users AS u
LEFT JOIN converters AS c
  USING (user_pseudo_id)
GROUP BY u.variant
ORDER BY u.variant = control_variant DESC, u.variant;
