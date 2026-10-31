/*
 02 · PRZYCHÓD TYGODNIOWY → pole przychodu w obu kalkulatorach
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/
 Test karty produktu: wejście = view_item, przychód z purchase.
*/

DECLARE window_end DATE DEFAULT DATE '2020-12-06';  -- dzień przed startem testu
DECLARE window_weeks INT64 DEFAULT 5;  -- to samo okno co max_weeks w 01; pełne tygodnie: każdy dzień tygodnia tyle samo razy

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    -- numer tygodnia w oknie: dni 0–6 od początku okna → 1, dni 7–13 → 2 itd.;
    -- początek okna = window_end − (window_weeks × 7 − 1), jak w WHERE niżej
    DIV(DATE_DIFF(
        PARSE_DATE('%Y%m%d', event_date),
        DATE_SUB(window_end, INTERVAL window_weeks * 7 - 1 DAY),
        DAY), 7) + 1
      AS week_no,
    -- przykładowy eksport ma USD; własny eksport: ecommerce.purchase_revenue
    ecommerce.purchase_revenue_in_usd AS revenue,
    -- brak transaction_id → każdy event to osobne zamówienie:
    -- NULLIF(x, y) zwraca NULL, gdy x = y, więc '(not set)' i '' stają się NULL,
    -- a IFNULL podstawia wtedy klucz unikalny dla eventu (user + czas)
    IFNULL(
      NULLIF(NULLIF(ecommerce.transaction_id, '(not set)'), ''),
      CONCAT(user_pseudo_id, '-', CAST(event_timestamp AS STRING))
    ) AS order_key
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE(
        '%Y%m%d',
        -- − 1, bo BETWEEN obejmuje oba końce: 5 tygodni = 35 dni = koniec − 34
        DATE_SUB(window_end, INTERVAL window_weeks * 7 - 1 DAY)
      )
      AND FORMAT_DATE('%Y%m%d', window_end)
    AND event_name IN ('view_item', 'purchase')
    -- Consent Mode bez zgody wysyła eventy bez user_pseudo_id — bez filtra
    -- GROUP BY skleiłby ich wszystkich w jednego użytkownika
    AND user_pseudo_id IS NOT NULL
),

exposed AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_view_ts
  FROM events
  WHERE event_name = 'view_item'
  GROUP BY user_pseudo_id
),

orders AS (
  -- jeden wiersz na zamówienie: GA4 dubluje purchase (odświeżenie strony
  -- podziękowania, podwójny tag), a zdublowany przychód liczy się podwójnie
  SELECT user_pseudo_id, event_timestamp, week_no, revenue
  FROM events
  WHERE event_name = 'purchase'
  -- ROW_NUMBER numeruje eventy w obrębie jednego order_key od najwcześniejszego;
  -- QUALIFY filtruje po wyniku funkcji okna (jak HAVING po agregacji) — zostaje 1.
  QUALIFY ROW_NUMBER() OVER (PARTITION BY order_key ORDER BY event_timestamp) = 1
),

purchases AS (
  -- tylko zakupy po pierwszym obejrzeniu karty produktu
  SELECT
    p.week_no,
    p.revenue
  FROM orders AS p
  JOIN exposed AS e
    ON e.user_pseudo_id = p.user_pseudo_id
    AND p.event_timestamp > e.first_view_ts
),

weekly AS (
  -- przychód każdego tygodnia okna; GENERATE_ARRAY daje wiersz także tygodniom
  -- bez zakupów, a LEFT JOIN + IFNULL wpisuje im 0 — inaczej mediana by je pominęła
  SELECT
    w AS week_no,
    IFNULL(SUM(p.revenue), 0) AS revenue
  FROM UNNEST(GENERATE_ARRAY(1, window_weeks)) AS w
  LEFT JOIN purchases AS p
    ON p.week_no = w
  GROUP BY w
)

/*
 ─── WYNIK ────────────────────────────────────────────────────────────────
 weekly_revenue        → kalkulatory: Tygodniowy przychód ze strony testowej
 weekly_revenue_median → to samo pole, gdy w oknie był pik sezonowy

 Przychód z window_weeks tygodni przed testem od użytkowników, którzy
 obejrzeli kartę produktu — tylko z zakupów PO pierwszym view_item.
 weekly_revenue = suma / liczba tygodni; jeden tydzień z pikiem
 (Black Friday, wyprzedaż) podnosi ją o część piku.
 weekly_revenue_median = środkowy tydzień; pik wypada, bo leży na skraju.
 Mediana wyraźnie niższa od średniej → w oknie był pik: do budżetu
 bierz medianę, bo po wdrożeniu przyjdą zwykłe tygodnie, nie szczyt.

 Przykład (liczby poglądowe): 4 tygodnie po 100 000 i Black Friday 225 000
 weekly_revenue | weekly_revenue_median
 ---------------+----------------------
        125 000 |               100 000

 → Przed testem, przy danych domyślnych: w 4 tygodniach wykryjesz
   +14,35%, czyli +17 931 zł tygodniowo.
 → Po teście, przy domyślnym wyniku: od +5 764 zł do +31 991 zł
   tygodniowo, najbardziej prawdopodobnie +18 878 zł.
*/
SELECT
  CAST(ROUND(SUM(revenue) / window_weeks) AS INT64) AS weekly_revenue,
  -- PERCENTILE_CONT to funkcja okna (wartość w każdym wierszu, OVER () = cała
  -- tabela), więc ANY_VALUE bierze ją raz; przy parzystej liczbie tygodni
  -- daje średnią dwóch środkowych
  CAST(ROUND(ANY_VALUE(median_revenue)) AS INT64) AS weekly_revenue_median
FROM (
  SELECT
    revenue,
    PERCENTILE_CONT(revenue, 0.5) OVER () AS median_revenue
  FROM weekly
);
