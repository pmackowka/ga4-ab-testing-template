/*
 03 · PO TEŚCIE → kalkulator „Po teście A/B”
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/
 Domyślnie test ab2 z gtm/01_dwa_warianty.html (v0/v1 po 50%). Pierwszy test
 to A/A w ab1: wynik ma być nieistotny i bez SRM, inaczej konfiguracja jest zła.
 Tabela w obu miejscach: `ab-test-sandbox.ga4_syntetyczny.events_*` (dane syntetyczne); własny eksport GA4: `twoj-projekt.analytics_123456789.events_*`.

 Uruchom najwcześniej 3 dni po test_end: GA4 jeszcze dopisuje dane.

 Wymaga w GTM: eventu ab_assign z ab_test i ab_variant oraz parametru slotu
 (zmienna cookie) na wszystkich eventach.
 Konwersja i przychód liczą się tylko po pierwszej ekspozycji. Zamówienie
 raz na transaction_id, przychód osoby przycięty do 99,9 percentyla.
*/

-- ===== DO UZUPEŁNIENIA: tylko te zmienne edytujesz, niżej nic nie zmieniaj =====
DECLARE test_start DATE DEFAULT DATE '2026-09-07';  -- = `start_testu` z rejestr_testow.csv: poniedziałek, w który opublikowano tag testu (pierwszy dzień okna)
DECLARE test_end DATE DEFAULT DATE '2026-09-20';  -- = `koniec_testu`: niedziela, ostatni dzień testu, co najmniej 3 dni temu
DECLARE test_name STRING DEFAULT 'ab2';  -- = `slot`: slot testu (ab1…ab10), TEST w tagu i nazwa parametru eventu
DECLARE control_variant STRING DEFAULT 'v0';  -- = `wariant_kontrolny`: wariant kontrolny, jeden z variants
DECLARE variants ARRAY<STRING> DEFAULT ['v0', 'v1'];  -- = `warianty` (w CSV rozdzielone `|`): wszystkie warianty, jak VARIANTS w tagu; inny wariant w danych przerywa zapytanie
DECLARE conversion_event STRING DEFAULT 'purchase';  -- = `zdarzenie_konwersji`: zdarzenie liczone jako konwersja
DECLARE exposure_events ARRAY<STRING> DEFAULT ['ab_assign', 'view_item'];  -- = `zdarzenia_ekspozycji` (w CSV rozdzielone `|`): zdarzenia, na których user wchodzi do testu (pierwsze z wariantem)
-- ===== KONIEC =====

ASSERT EXTRACT(DAYOFWEEK FROM test_start) = 2
  AS 'test_start musi być poniedziałkiem';
ASSERT EXTRACT(DAYOFWEEK FROM test_end) = 1 AND test_end > test_start
  AS 'test_end musi być niedzielą po test_start: pełne tygodnie';
ASSERT control_variant IN UNNEST(variants)
  AS 'control_variant musi być na liście variants';
ASSERT test_end <= DATE_SUB(CURRENT_DATE(), INTERVAL 3 DAY)
  AS 'uruchom najwcześniej 3 dni po test_end: GA4 jeszcze dopisuje dane';
ASSERT (
  SELECT COUNT(DISTINCT _TABLE_SUFFIX)
  FROM `ab-test-sandbox.ga4_syntetyczny.events_*`
  WHERE _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', test_start)
    AND FORMAT_DATE('%Y%m%d', test_end)
) = DATE_DIFF(test_end, test_start, DAY) + 1
  AS 'brakuje dziennych tabel eksportu w okresie testu';

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    NULLIF(NULLIF(ecommerce.transaction_id, '(not set)'), '') AS transaction_id,
    ecommerce.purchase_revenue AS revenue,
    IF(
      event_name = 'ab_assign',
      IF(
        (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test') = test_name,
        (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_variant'),
        NULL
      ),
      NULLIF((SELECT value.string_value FROM UNNEST(event_params) WHERE key = test_name), 'out')
    ) AS ab_variant
  FROM `ab-test-sandbox.ga4_syntetyczny.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE('%Y%m%d', test_start)
      AND FORMAT_DATE('%Y%m%d', test_end)
    AND user_pseudo_id IS NOT NULL
),

users_assigned AS (
  SELECT
    user_pseudo_id,
    MIN(IF(event_name IN UNNEST(exposure_events), event_timestamp, NULL))
      AS first_exposure_ts,
    ARRAY_AGG(
      IF(event_name IN UNNEST(exposure_events), ab_variant, NULL)
      IGNORE NULLS ORDER BY event_timestamp LIMIT 1
    )[SAFE_OFFSET(0)] AS variant,
    COUNT(DISTINCT ab_variant) AS variants_seen,
    COUNT(DISTINCT IF(event_name = 'ab_assign', event_timestamp, NULL)) AS assignments
  FROM events
  WHERE ab_variant IS NOT NULL
  GROUP BY user_pseudo_id
  HAVING first_exposure_ts IS NOT NULL
),

converters AS (
  SELECT DISTINCT u.user_pseudo_id
  FROM users_assigned AS u
  JOIN events AS p
    ON p.user_pseudo_id = u.user_pseudo_id
    AND p.event_name = conversion_event
    AND p.event_timestamp > u.first_exposure_ts
),

user_revenue AS (
  SELECT user_pseudo_id, SUM(revenue) AS revenue
  FROM (
    SELECT
      u.user_pseudo_id,
      IFNULL(p.transaction_id, CAST(p.event_timestamp AS STRING)) AS transaction_key,
      ANY_VALUE(p.revenue) AS revenue
    FROM users_assigned AS u
    JOIN events AS p
      ON p.user_pseudo_id = u.user_pseudo_id
      AND p.event_name = conversion_event
      AND p.event_timestamp > u.first_exposure_ts
    GROUP BY u.user_pseudo_id, transaction_key
  )
  GROUP BY user_pseudo_id
),

users_final AS (
  SELECT
    u.*,
    c.user_pseudo_id IS NOT NULL AS converted,
    IF(u.variants_seen = 1,
      LEAST(IFNULL(r.revenue, 0), IFNULL(PERCENTILE_CONT(
        IF(u.variants_seen = 1 AND r.revenue > 0, r.revenue, NULL), 0.999
      ) OVER (), 0)),
      NULL) AS revenue
  FROM users_assigned AS u
  LEFT JOIN converters AS c
    USING (user_pseudo_id)
  LEFT JOIN user_revenue AS r
    USING (user_pseudo_id)
)

SELECT
  CASE
    WHEN LOGICAL_OR(u.variant NOT IN UNNEST(variants)) OVER ()
      THEN ERROR('w danych jest wariant spoza listy variants — sprawdź tag i zmienną GTM')
    WHEN COUNT(*) OVER () < ARRAY_LENGTH(variants)
      THEN ERROR(FORMAT('w danych brakuje wariantu z listy %t', variants))
    WHEN u.variant = control_variant THEN 'A (kontrola)'
    ELSE CONCAT('B (wariant ', u.variant, ')')
  END AS calculator_field,
  COUNTIF(u.variants_seen = 1) AS users,
  COUNTIF(u.variants_seen = 1 AND u.converted) AS converters,
  ROUND(IFNULL(SUM(u.revenue), 0), 2) AS revenue,
  ROUND(IFNULL(SAFE_DIVIDE(SUM(u.revenue), COUNTIF(u.variants_seen = 1)), 0), 2) AS revenue_per_user,
  ROUND(IFNULL(STDDEV_SAMP(u.revenue), 0), 2) AS revenue_sd,
  COUNTIF(u.variants_seen > 1) AS excluded_mixed,
  COUNTIF(u.assignments > 1) AS reassigned,
  COUNTIF(u.assignments = 0) AS no_assignment
FROM users_final AS u
GROUP BY u.variant
ORDER BY u.variant = control_variant DESC, u.variant;

/*
 Wynik dla testu ab2 (dane syntetyczne, 2026-09-07 – 2026-09-20, domyślne parametry; prawdziwy efekt v1 +10%):
 calculator_field | users  | converters | revenue    | revenue_per_user | revenue_sd | excluded_mixed | reassigned | no_assignment
 -----------------+--------+------------+------------+------------------+------------+----------------+------------+--------------
 A (kontrola)     | 64 266 |      2 038 | 564 521.87 |             8.78 |      67.30 |             68 |        143 |           148
 B (wariant v1)   | 64 070 |      2 313 | 638 626.47 |             9.97 |      70.79 |             85 |        161 |           143

 Kalkulator: users, converters; w trybie przychodu revenue_per_user i revenue_sd.
 Kontrola jakości, do kalkulatora nie idzie:
 - excluded_mixed: 2+ warianty, wyjęci z users; różnica między wierszami
   większa niż 2 × √(suma obu) jest podejrzana (tu 17 < 25, w normie)
 - reassigned: 2+ ab_assign, ciasteczko testu zniknęło i tag losował ponownie
 - no_assignment: wariant bez ab_assign, nowe _ga albo zgubiony hit
*/
