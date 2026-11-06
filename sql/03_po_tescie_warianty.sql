/*
 03 · PO TEŚCIE → kalkulator „Po teście A/B”
 https://pmdata.pl/kalkulatory/istotnosc-testu-ab/
 Pierwszy test to A/A w slocie ab1 (ten sam tag 01, v1 bez zmiany na stronie):
 test_name = 'ab1', jego daty; wynik ma być nieistotny i bez SRM, inaczej
 konfiguracja jest zepsuta. Domyślnie liczy kolejny test z gtm/01_dwa_warianty.html
 (klucz ab2, v0/v1 po 50%): wariant
 losuje tag w przeglądarce i zapisuje w first-party cookie, SQL tylko go czyta
 (https://pmdata.pl/artykuly/wlasne-testy-ab-gtm-firebase/). Inne tagi z gtm/:
 zmień test_name i variants ('out' z 03/04 zapytanie pomija). Wymaga w GTM:
 - tagu GA4 Event ab_assign z parametrami ab_test i ab_variant (obowiązkowy)
   — z niego zapytanie wie, kto i kiedy wszedł do testu;
 - parametru o nazwie slotu (ab1…ab10) = zmienna „Własny plik cookie” slotu
   na wszystkich eventach (zalecany) — bez niego view_item nie jest
   ekspozycją, excluded_mixed nie wyłapie ponownego losowania, a no_assignment
   jest zawsze 0 (reassigned liczy z samego ab_assign i działa dalej).
 Testy w innych slotach mogą trwać równolegle: zapytanie czyta tylko
 parametr test_name, a z ab_assign tylko ten z ab_test = test_name.
 Tabelę `twoj-projekt.analytics_123456789.events_*` podmień w obu miejscach.
*/

DECLARE test_start DATE DEFAULT DATE '2026-09-07';  -- poniedziałek publikacji tagu
DECLARE test_end DATE DEFAULT DATE '2026-10-04';    -- niedziela: ostatni dzień testu
DECLARE test_name STRING DEFAULT 'ab2';             -- slot = TEST w tagu = nazwa parametru eventu
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
    -- ab_assign przypisuje do jednego testu: wariant tylko, gdy ab_test to nasz
    -- slot (parametry slotów na ab_assign należą do innych testów); pozostałe
    -- eventy niosą wariant w parametrze o nazwie slotu
    IF(
      event_name = 'ab_assign',
      IF(
        (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_test') = test_name,
        (SELECT value.string_value FROM UNNEST(event_params) WHERE key = 'ab_variant'),
        NULL
      ),
      -- zmienna cookie wysyła surową wartość, także 'out' (poza testem) — to nie wariant
      NULLIF((SELECT value.string_value FROM UNNEST(event_params) WHERE key = test_name), 'out')
    ) AS ab_variant
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
    COUNT(DISTINCT ab_variant) AS variants_seen,
    -- tag wysyła ab_assign tylko przy losowaniu: 2+ = ciasteczko testu zginęło i tag
    -- losował ponownie, 0 = wariant z ciasteczka pod nowym user_pseudo_id (usunięte _ga)
    -- albo zgubiony hit ab_assign
    -- różne event_timestamp: duplikat eventu w eksporcie to jedno losowanie
    COUNT(DISTINCT IF(event_name = 'ab_assign', event_timestamp, NULL)) AS assignments
  FROM events
  WHERE ab_variant IS NOT NULL
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
 reassigned       → do kalkulatora nie idzie: kontrola jakości danych
 no_assignment    → do kalkulatora nie idzie: kontrola jakości danych

 users: unikalni użytkownicy od pierwszej ekspozycji w okresie testu.
 converters: ci z nich, którzy kupili PO pierwszej ekspozycji; osoby, nie
 zamówienia. Zapytanie przerywa się błędem, gdy brakuje kontroli albo
 wariantu albo w danych jest wariant spoza listy variants (tag z innymi
 wartościami albo literówka w zmiennej GTM).

 excluded_mixed: użytkownicy z 2+ wariantami (variants_seen > 1), wyjęci
 z users i converters, bo nie wiadomo, któremu wariantowi przypisać ich
 zakup. Wiersz = wariant ich PIERWSZEJ ekspozycji. Przy n wariantach to ok.
 (n−1)/n ponownie wylosowanych (przy 2 — połowa); reszta trafiła przypadkiem
 w ten sam wariant (variants_seen = 1) i widać ją tylko w reassigned.

 reassigned: użytkownicy z 2+ ab_assign (assignments > 1) — pełny wolumen
 utraty ciasteczka testu przy zachowanym _ga, razem z excluded_mixed. Ci
 z jednym wariantem zostają w users.
 no_assignment: użytkownicy z wariantem, ale bez ab_assign (assignments = 0)
 — przyszli z ciasteczkiem testu pod nowym user_pseudo_id (usunięte _ga),
 więc ta sama osoba może być w users dwa razy, albo hit ab_assign zginął
 (adblock, wyjście ze strony przed wysyłką). Zostają w users.
 Niewidoczny zostaje przypadek, gdy znikają naraz _ga i ciasteczko testu:
 nowy użytkownik z nowym losowaniem wygląda jak każdy inny.
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
 calculator_field | users  | converters | excluded_mixed | reassigned | no_assignment
 -----------------+--------+------------+----------------+------------+--------------
 A (kontrola)     | 36 700 |        734 |            410 |        826 |         1 190
 B (wariant v1)   | 36 750 |        846 |            398 |        801 |         1 172

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
  COUNTIF(u.variants_seen > 1) AS excluded_mixed,
  COUNTIF(u.assignments > 1) AS reassigned,
  COUNTIF(u.assignments = 0) AS no_assignment
FROM users_assigned AS u
LEFT JOIN converters AS c
  USING (user_pseudo_id)
GROUP BY u.variant
ORDER BY u.variant = control_variant DESC, u.variant;
