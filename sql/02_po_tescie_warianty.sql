/*
 02 · PO TEŚCIE → kalkulator „Po teście A/B”
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/
 Wariant z first-party cookie ustawianego w GTM:
 https://pmdata.pl/artykuly/wlasne-testy-ab-gtm-firebase/
 Tagi GA4 wysyłają parametry ab_test (nazwa testu) i ab_variant (wartość
 ciasteczka) — na ab_assign i na każdym evencie, do którego je dodasz.
*/

-- TRUE: przykładowy eksport GA4 nie ma testu, wariant z hasha user_pseudo_id;
-- na własnych danych ustaw FALSE
DECLARE demo_mode BOOL DEFAULT TRUE;
DECLARE test_start DATE DEFAULT DATE '2020-12-07';  -- poniedziałek
DECLARE test_end DATE DEFAULT DATE '2021-01-03';    -- niedziela
DECLARE test_name STRING DEFAULT 'ab_cta';          -- wartość parametru ab_test
DECLARE control_variant STRING DEFAULT 'v0';
-- punkt ekspozycji: user wchodzi do testu na pierwszym z tych eventów z wariantem;
-- ab_assign zostaw, gdy losujesz na stronie testowej, usuń, gdy losujesz wcześniej
DECLARE exposure_events ARRAY<STRING> DEFAULT ['ab_assign', 'view_item'];

ASSERT EXTRACT(DAYOFWEEK FROM test_start) = 2
  AS 'test_start musi być poniedziałkiem';
ASSERT EXTRACT(DAYOFWEEK FROM test_end) = 1 AND test_end > test_start
  AS 'test_end musi być niedzielą po test_start: pełne tygodnie';

WITH events AS (
  -- bez filtra na event_name: BigQuery liczy koszt od kolumn, nie wierszy,
  -- a wariant z każdego eventu wyłapuje ponowne losowanie
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    IF(
      demo_mode,
      test_name,
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test')
    ) AS ab_test,
    IF(
      demo_mode,
      IF(MOD(ABS(FARM_FINGERPRINT(user_pseudo_id)), 2) = 0, 'v0', 'v1'),
      (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_variant')
    ) AS ab_variant
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', test_start)
      AND FORMAT_DATE('%Y%m%d', test_end)
),

users_assigned AS (
  -- jeden wiersz na eksponowanego użytkownika: pierwsza ekspozycja, jej wariant
  -- i liczba wariantów na WSZYSTKICH eventach testu (wygasłe cookie → nowe losowanie)
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
  -- zakup PO pierwszej ekspozycji; DISTINCT = osoby, nie zamówienia;
  -- zakup bez parametru też się liczy — wariant bierzemy z przypisania
  SELECT DISTINCT u.user_pseudo_id
  FROM users_assigned AS u
  JOIN events AS p
    ON p.user_pseudo_id = u.user_pseudo_id
    AND p.event_name = 'purchase'
    AND p.event_timestamp > u.first_exposure_ts
)

/*
 ─── WYNIK ────────────────────────────────────────────────────────────────
 calculator_field → który wiersz kalkulatora: A (kontrola) albo B (wariant)
 users            → kalkulator: Użytkownicy A / Użytkownicy B
 converters       → kalkulator: Konwertujący A / Konwertujący B
 excluded_mixed   → do kalkulatora nie idzie: wykluczeni z 2+ wariantami,
                    przypisani do wariantu pierwszej ekspozycji

 users: unikalni użytkownicy od pierwszej ekspozycji w okresie testu.
 converters: ci z nich, którzy kupili PO pierwszej ekspozycji; osoby, nie
 zamówienia. excluded_mixed wyraźnie różne między wierszami = wykluczenie
 zależy od wariantu, wynik obciążony — szukaj błędu w tagu albo ciasteczku.
 Brak control_variant w danych przerywa zapytanie błędem.

 Przykład (liczby poglądowe, zgodne z domyślnymi danymi kalkulatora):
 calculator_field | users  | converters | excluded_mixed
 -----------------+--------+------------+---------------
 A (kontrola)     | 36 700 |        734 |            410
 B (wariant v1)   | 36 750 |        846 |            398

 → kalkulator: „Wdrażaj B”, p-value 0,0048, wzrost od +4,61% do +25,59%.
*/
SELECT
  CASE
    WHEN NOT LOGICAL_OR(u.variant = control_variant) OVER ()
      THEN ERROR(FORMAT("brak wariantu kontrolnego '%s' w danych", control_variant))
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
