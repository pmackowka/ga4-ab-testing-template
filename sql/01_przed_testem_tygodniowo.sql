/*
================================================================================
 01 · PRZED TESTEM — kalkulator „Przed testem A/B”
 https://pmdata.pl/kalkulatory/wielkosc-proby-test-ab/
================================================================================

 SCENARIUSZ: sklep e-commerce testuje nową wersję KARTY PRODUKTU.
 Zdarzenia rekomendowane GA4 (developers.google.com/analytics/devguides/
 collection/ga4/reference/events):
   view_item  — wyświetlenie karty produktu = wejście do testu
   purchase   — zakup = konwersja

 CO LICZY: kilka pełnych tygodni przed testem — ilu unikalnych użytkowników
 obejrzało kartę produktu i ilu z nich kupiło PO tym wejściu. Ostatni wiersz
 (ŚREDNIA) wpisujesz do kalkulatora.

 ─── Pola kalkulatora z tego zapytania ──────────────────────────────────────

 Użytkownicy w tygodniu   ← users_weekly
   Unikalni użytkownicy z view_item w tygodniu, łącznie dla wszystkich wariantów.
   Użytkownicy, nie sesje: test losuje ludzi (cookie), a sesje tej samej osoby
   nie są niezależne — liczone osobno zaniżają błąd i dają fałszywe pozytywy.
   user_pseudo_id = przeglądarka: telefon i laptop jednej osoby to dwóch
   użytkowników. Narzędzie do testów myli się tak samo, więc plan i wynik
   zostają spójne.

 Konwertujący w tygodniu  ← converters_weekly
   Ilu z nich kupiło PO pierwszym view_item w tym tygodniu. Osoby, nie
   zamówienia: trzy zakupy jednej osoby to jeden konwertujący. Zakup sprzed
   wejścia na kartę nie mógł zależeć od wariantu, więc się nie liczy.

 CR (conversion rate)     ← cr_pct (kontrolnie — kalkulator liczy go sam)
   CR = konwertujący / użytkownicy.

 ─── Pola kalkulatora, których nie da się policzyć z danych ─────────────────

 Najmniejszy wzrost do wykrycia (MDE, %)
   Najmniejszy wzrost CR, który ma znaczenie biznesowe — NIE wzrost, którego
   się spodziewasz. Względnie: +15% przy CR 2% = CR wariantu 2,3% (+0,3 pp).
   Najmocniej wpływa na długość testu: 2× mniejsze MDE = 4× więcej użytkowników.
   Jak wybrać, gdy biznes nie wie:
   1) z tabeli w kalkulatorze „jakie MDE wykryjesz po N tygodniach” — pytasz
      biznes, czy zmiana realnie może tyle dać; jeśli nie, test nie ma sensu,
   2) próg opłacalności: koszt zmiany / przychód ze strony w okresie zwrotu,
   3) historia: typowy wzrost wygranych testów w firmie.

 Liczba wariantów razem z kontrolą
   A/B = 2. Przy k > 2 kalkulator dzieli próg α przez k − 1 (korekta
   Bonferroniego), żeby więcej porównań nie dawało więcej fałszywych pozytywów.
   Koszt: każdy wariant potrzebuje więcej użytkowników.

 Poziom ufności (1 − α), zwykle 95%
   Chroni przed FAŁSZYWYM POZYTYWEM (błąd I rodzaju): przy 95% w 1 teście na 20,
   w którym zmiana nic nie daje, ogłosisz wzrost, którego nie ma.

 Moc testu (1 − β), zwykle 80%
   Chroni przed FAŁSZYWYM NEGATYWEM (błąd II rodzaju): przy 80% realny wzrost
   równy MDE wykryjesz w 4 testach na 5, w piątym go przeoczysz.

     Macierz błędów      | wdrażasz B             | nie wdrażasz B
     --------------------+------------------------+-----------------------
     B naprawdę = A      | fałszywy pozytyw (α)   | trafnie
     B naprawdę lepszy   | trafnie                | fałszywy negatyw (β)

 Rodzaj testu
   Dwustronny (domyślny) sprawdza wzrost i spadek. Jednostronny sprawdza tylko
   wzrost — potrzebuje ~21% mniej użytkowników, ale nie wykryje, że karta
   produktu szkodzi. Wybierasz przed testem, nie zmieniasz po wyniku.

 Najdłużej możesz testować (tygodnie)
   Ile tygodni karta, ceny i kampanie mogą zostać bez zmian. Zawsze pełne
   tygodnie (w poniedziałek i w sobotę kupują inni ludzie). Powyżej ~6 tygodni
   test psuje kasowanie cookies (ITP w Safari) i sezonowość.

 ─── Dlaczego kilka tygodni, a nie jeden ───────────────────────────────────

 Jeden tydzień bywa nietypowy (promocja, święto, awaria). Gdy tygodnie mocno
 się różnią, nie bierz średniej w ciemno — sprawdź, skąd różnica.
 Konwersja liczona w tym samym tygodniu co wejście; dla testu 2+ tygodnie
 dokładniejsze jest zapytanie 02.

 Dane: publiczny przykładowy eksport GA4 (Google Merchandise Store,
 2020-11-01 – 2021-01-31). Własny eksport: podmień nazwę tabeli w CTE events.
================================================================================
*/

-- poniedziałek, od którego liczymy pełne tygodnie
DECLARE first_week_start DATE DEFAULT DATE '2020-11-02';
-- ile pełnych tygodni (zalecane: 4)
DECLARE weeks_count INT64 DEFAULT 4;

-- tydzień = poniedziałek–niedziela; inaczej tygodnie się przesuną
ASSERT EXTRACT(DAYOFWEEK FROM first_week_start) = 2
  AS 'first_week_start musi być poniedziałkiem';

WITH events AS (
  -- tylko karta produktu i zakup, tylko z wybranych tygodni;
  -- _TABLE_SUFFIX ogranicza skanowane dane, a więc koszt zapytania
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
    AND event_name IN ('view_item', 'purchase')
),

exposed AS (
  -- Użytkownicy w tygodniu: każdy raz na tydzień,
  -- z momentem PIERWSZEGO wyświetlenia karty produktu
  SELECT
    week_start,
    user_pseudo_id,
    MIN(event_timestamp) AS first_view_ts
  FROM events
  WHERE event_name = 'view_item'
  GROUP BY week_start, user_pseudo_id
),

converted AS (
  -- Konwertujący w tygodniu: zakup PO pierwszym view_item, w tym samym
  -- tygodniu; DISTINCT = osoby, nie zamówienia
  SELECT DISTINCT
    e.week_start,
    e.user_pseudo_id
  FROM exposed AS e
  JOIN events AS p
    ON p.user_pseudo_id = e.user_pseudo_id
    AND p.week_start = e.week_start
    AND p.event_name = 'purchase'
    AND p.event_timestamp > e.first_view_ts
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

-- tygodnie — czy są do siebie podobne
SELECT
  CAST(week_start AS STRING) AS week,
  users_weekly,
  converters_weekly,
  ROUND(SAFE_DIVIDE(converters_weekly, users_weekly) * 100, 2) AS cr_pct
FROM per_week

UNION ALL

-- ten wiersz wpisujesz do kalkulatora
SELECT
  'ŚREDNIA → do kalkulatora' AS week,
  CAST(ROUND(AVG(users_weekly)) AS INT64) AS users_weekly,
  CAST(ROUND(AVG(converters_weekly)) AS INT64) AS converters_weekly,
  ROUND(SAFE_DIVIDE(SUM(converters_weekly), SUM(users_weekly)) * 100, 2) AS cr_pct
FROM per_week

ORDER BY week;
