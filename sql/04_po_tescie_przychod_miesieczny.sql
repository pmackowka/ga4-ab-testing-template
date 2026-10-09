/*
================================================================================
 04 · PO TEŚCIE — przychód do przeliczenia wzrostu na złotówki
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/
================================================================================

 Co liczy: przychód z ostatnich 30 dni od użytkowników, którzy weszli na stronę
 objętą testem — z zakupów PO pierwszym wejściu. To baza, od której kalkulator
 liczy wpływ wzrostu CR na przychód.

 ─── Pole kalkulatora, które wypełnia to zapytanie ───────────────────────────

 „Miesięczny przychód ze strony testowej (zł)”   ← kolumna monthly_revenue
   Przychód od użytkowników, którzy weszli na stronę objętą testem; pozwala
   przeliczyć wzrost na złotówki.

 Kalkulator mnoży ten przychód przez ZAKRES wzrostu (przedział ufności), nie
 przez jedną liczbę: „od +23 055 zł do +127 965 zł”, a nie „+75 510 zł”.
 Prognoza z jednego punktu obiecuje wzrost, który leży gdzieś w przedziale,
 czasem blisko zera.

 ─── Założenia, które warto znać ────────────────────────────────────────────

 • Liczymy przychód sprzed testu (stan „jak jest”), bo wzrost odnosi się do
   kontroli, czyli do obecnej wersji strony.
 • Przeliczenie zakłada, że wartość zamówienia się nie zmienia — test mierzył
   CR, nie przychód na użytkownika. Jeśli wariant zmienia też koszyk, mierz
   przychód na użytkownika osobnym testem.
 • 30 dni, nie miesiąc kalendarzowy — miesiące mają różną liczbę dni i weekendów.

 ─── Kolumna przychodu ──────────────────────────────────────────────────────

 Publiczny przykładowy eksport ma przychód w USD: ecommerce.purchase_revenue_in_usd.
 W Twoim eksporcie GA4 użyj ecommerce.purchase_revenue (waluta sklepu, np. PLN)
 — podmień nazwę kolumny w CTE `purchases`.
================================================================================
*/

-- ─── Parametry ────────────────────────────────────────────────────────────────

-- ostatni dzień okna (dzień przed startem testu)
DECLARE window_end DATE DEFAULT DATE '2020-12-06';
DECLARE window_days INT64 DEFAULT 30;
DECLARE exposure_event STRING DEFAULT 'view_item';

-- ─── Zapytanie ────────────────────────────────────────────────────────────────

WITH events AS (
  SELECT
    user_pseudo_id,
    event_name,
    event_timestamp,
    -- przykładowy eksport: USD; własny eksport: ecommerce.purchase_revenue
    ecommerce.purchase_revenue_in_usd AS revenue
  FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
  WHERE
    _TABLE_SUFFIX BETWEEN FORMAT_DATE(
        '%Y%m%d',
        DATE_SUB(window_end, INTERVAL window_days - 1 DAY)
      )
      AND FORMAT_DATE('%Y%m%d', window_end)
    AND event_name IN (exposure_event, 'purchase')
),

exposed AS (
  SELECT
    user_pseudo_id,
    MIN(event_timestamp) AS first_exposure_ts
  FROM events
  WHERE event_name = exposure_event
  GROUP BY user_pseudo_id
),

purchases AS (
  -- tylko zakupy po pierwszym wejściu na stronę testową
  SELECT
    p.user_pseudo_id,
    p.revenue
  FROM events AS p
  JOIN exposed AS e
    ON e.user_pseudo_id = p.user_pseudo_id
    AND p.event_timestamp > e.first_exposure_ts
  WHERE p.event_name = 'purchase'
)

SELECT
  window_days AS days,
  (SELECT COUNT(*) FROM exposed) AS users_on_test_page,
  COUNT(DISTINCT user_pseudo_id) AS buyers,
  COUNT(*) AS purchases,
  -- „Miesięczny przychód ze strony testowej” → wpisz do kalkulatora
  CAST(ROUND(IFNULL(SUM(revenue), 0)) AS INT64) AS monthly_revenue
FROM purchases;
