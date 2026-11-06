/*
 GENERATOR · syntetyczny eksport GA4 dla projektu dbt
 Tworzy w osobnym datasecie tabele dzienne events_RRRRMMDD w schemacie eksportu GA4 — tylko
 kolumny, które czyta stg_ga4__zdarzenia — ze scenariuszem testów z dbt/seeds/rejestr_testow.csv.
 Scenariusz: wizyta = view_item; część przechodzi do begin_checkout, z niego część do purchase.
 Testy na karcie produktu (ab1–ab4, ab1 = A/A) zmieniają przejście do checkoutu, test checkoutu (ab5)
 przejście do zakupu — efekt w DECLARE testy to względna zmiana CR wariantu wobec kontroli.
 Losowość z FARM_FINGERPRINT, nie RAND(): ten sam dzień generuje się zawsze tak samo, więc
 kolejne dni można dogenerować osobno, a powracający użytkownik ma ten sam wariant.
 Uruchomienie bez zmian nadrabia: generuje dni od ostatniej tabeli w zbiorze do wczoraj, także
 po kilku dniach przerwy; gdy wszystko jest, nic nie robi. Podane data_od podmienia dni od niego.
 Uruchom z lokalizacją danych EU (Ustawienia zapytania): zbiór jest czytany tylko przez EXECUTE
 IMMEDIATE, więc BigQuery nie wywnioskuje regionu i może uruchomić zadanie w US.
*/

DECLARE projekt_docelowy STRING DEFAULT 'twoj-projekt';
DECLARE zbior_docelowy STRING DEFAULT 'ga4_syntetyczny';    -- = vars.ga4_zbior_danych w dbt
DECLARE data_startu DATE DEFAULT DATE '2026-08-24';         -- = vars.ga4_data_startu; pierwszy dzień pustego zbioru
DECLARE data_od DATE DEFAULT NULL;                          -- NULL = dzień po ostatniej tabeli events_ w zbiorze
DECLARE data_do DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);
DECLARE wizyty_dziennie INT64 DEFAULT 10000;
DECLARE udzial_powracajacych FLOAT64 DEFAULT 0.3;           -- wizyty osób z poprzednich 28 dni
DECLARE cr_koszyka FLOAT64 DEFAULT 0.10;                    -- view_item → begin_checkout
DECLARE cr_zakupu FLOAT64 DEFAULT 0.30;                     -- begin_checkout → purchase
-- inna wartość = inne zachowanie tych samych użytkowników, jak ponowne przetworzenie dnia przez GA4
DECLARE ziarno STRING DEFAULT 'a';
-- kopia seeda + efekt każdego wariantu; kontrola pierwsza na liście, efekt 0
DECLARE testy ARRAY<STRUCT<slot STRING, start_testu DATE, koniec_testu DATE, warianty ARRAY<STRING>,
  efekty ARRAY<FLOAT64>, etap STRING>> DEFAULT [
  ('ab1', DATE '2026-08-24', DATE '2026-09-06', ['v0', 'v1'], [0.0, 0.0], 'karta'),   -- test A/A: v1 = kontrola
  ('ab2', DATE '2026-09-07', DATE '2026-10-04', ['v0', 'v1'], [0.0, 0.10], 'karta'),
  ('ab3', DATE '2026-10-05', DATE '2026-11-01', ['v0', 'v1', 'v2'], [0.0, 0.0, 0.12], 'karta'),
  ('ab4', DATE '2026-11-02', DATE '2026-12-13', ['v0', 'v1'], [0.0, -0.05], 'karta'),
  ('ab5', DATE '2026-11-02', DATE '2026-11-29', ['v0', 'v1'], [0.0, 0.10], 'checkout')
];
-- usterki (NULL = wyłączona), każda ma wywołać inny test dbt
DECLARE usterka_srm_slot STRING DEFAULT NULL;               -- sprawdz_srm (warn)
DECLARE usterka_srm_udzial_kontroli FLOAT64 DEFAULT 0.53;
DECLARE usterka_brak_dnia DATE DEFAULT NULL;                -- sprawdz_komplet_dni_ga4 (error); wymaga data_od <= ten dzień

DECLARE dzien DATE;
DECLARE liczba_nowych INT64 DEFAULT CAST(ROUND(wizyty_dziennie * (1 - udzial_powracajacych)) AS INT64);

ASSERT NOT EXISTS (SELECT 1 FROM UNNEST(testy) AS t WHERE ARRAY_LENGTH(t.efekty) != ARRAY_LENGTH(t.warianty))
  AS 'każdy test musi mieć tyle efektów, ile wariantów';

-- liczba z [0, 1) stała dla klucza — zamiennik RAND()
CREATE TEMP FUNCTION los(klucz STRING) AS (MOD(ABS(FARM_FINGERPRINT(klucz)), 1000000) / 1000000);

-- region jak w profiles.yml: BigQuery nie łączy danych między regionami
EXECUTE IMMEDIATE FORMAT("CREATE SCHEMA IF NOT EXISTS `%s.%s` OPTIONS (location = 'EU')",
  projekt_docelowy, zbior_docelowy);

IF data_od IS NULL THEN
  -- tylko metadane zbioru, bez skanu danych; dziura w środku (usterka_brak_dnia) zostaje
  EXECUTE IMMEDIATE FORMAT("""
    SELECT DATE_ADD(MAX(PARSE_DATE('%%Y%%m%%d', SUBSTR(table_name, 8))), INTERVAL 1 DAY)
    FROM `%s.%s.INFORMATION_SCHEMA.TABLES`
    WHERE REGEXP_CONTAINS(table_name, r'^events_\\d{8}$')""", projekt_docelowy, zbior_docelowy)
    INTO data_od;
  SET data_od = IFNULL(data_od, data_startu);
END IF;
SET dzien = data_od;

WHILE dzien <= data_do DO
  IF dzien = usterka_brak_dnia THEN
    EXECUTE IMMEDIATE FORMAT('DROP TABLE IF EXISTS `%s.%s.events_%s`',
      projekt_docelowy, zbior_docelowy, FORMAT_DATE('%Y%m%d', dzien));
  ELSE
    CREATE OR REPLACE TEMP TABLE zdarzenia_dnia AS
    WITH wizyty AS (
      -- pierwsze liczba_nowych wizyt to nowi użytkownicy, reszta wraca z jednego z 28 poprzednich dni
      SELECT
        n,
        n < liczba_nowych AS czy_nowy,
        IF(n < liczba_nowych, dzien,
          DATE_SUB(dzien, INTERVAL 1 + CAST(FLOOR(los(FORMAT('lag|%t|%d', dzien, n)) * 28) AS INT64) DAY))
          AS dzien_pierwszej_wizyty,
        IF(n < liczba_nowych, n, CAST(FLOOR(los(FORMAT('idx|%t|%d', dzien, n)) * liczba_nowych) AS INT64))
          AS nr_uzytkownika,
        -- start wizyty do 23:00 UTC, żeby wszystkie eventy zostały w tym samym dniu
        TIMESTAMP_ADD(TIMESTAMP(dzien), INTERVAL CAST(FLOOR(los(FORMAT('%s|t|%t|%d', ziarno, dzien, n)) * 82800) AS INT64) SECOND)
          AS start_wizyty
      FROM UNNEST(GENERATE_ARRAY(0, wizyty_dziennie - 1)) AS n
    ),

    uzytkownicy AS (
      -- user_pseudo_id jak w GA4: liczba + znacznik czasu pierwszej wizyty
      SELECT
        *,
        CONCAT(
          CAST(1000000000 + MOD(ABS(FARM_FINGERPRINT(FORMAT('u|%t|%d', dzien_pierwszej_wizyty, nr_uzytkownika))), 1000000000) AS STRING),
          '.', CAST(UNIX_SECONDS(TIMESTAMP(dzien_pierwszej_wizyty)) AS STRING)) AS id_uzytkownika
      FROM wizyty
    ),

    przydzialy AS (
      -- wariant z hasha użytkownika i testu = cookie: ten sam przy każdej wizycie
      SELECT
        u.n,
        t.slot,
        t.etap,
        t.warianty,
        t.efekty,
        los(FORMAT('w|%s|%s|%t', u.id_uzytkownika, t.slot, t.start_testu)) AS b,
        IF(t.slot = usterka_srm_slot, usterka_srm_udzial_kontroli, 1 / ARRAY_LENGTH(t.warianty)) AS udzial_kontroli
      FROM uzytkownicy AS u
      CROSS JOIN UNNEST(testy) AS t
      WHERE dzien BETWEEN t.start_testu AND t.koniec_testu
    ),

    warianty_wizyt AS (
      SELECT
        n,
        slot,
        etap,
        warianty[OFFSET(nr)] AS wariant,
        efekty[OFFSET(nr)] AS efekt
      FROM (
        SELECT
          *,
          IF(b < udzial_kontroli, 0,
            1 + LEAST(ARRAY_LENGTH(warianty) - 2,
              CAST(FLOOR((b - udzial_kontroli) / (1 - udzial_kontroli) * (ARRAY_LENGTH(warianty) - 1)) AS INT64)))
            AS nr
        FROM przydzialy
      )
    ),

    sciezki AS (
      -- efekty testów aktywnych równolegle mnożą się; przejścia losowane niezależnie od wariantu
      SELECT
        u.*,
        los(FORMAT('%s|k|%t|%d', ziarno, dzien, u.n)) < cr_koszyka * IFNULL(w.mnoznik_karta, 1) AS czy_koszyk,
        los(FORMAT('%s|z|%t|%d', ziarno, dzien, u.n)) < cr_zakupu * IFNULL(w.mnoznik_checkout, 1) AS czy_zakup_z_koszyka,
        IFNULL(w.karta, []) AS karta,
        IFNULL(w.checkout, []) AS checkout
      FROM uzytkownicy AS u
      LEFT JOIN (
        SELECT
          n,
          EXP(SUM(IF(etap = 'karta', LN(1 + efekt), 0))) AS mnoznik_karta,
          EXP(SUM(IF(etap = 'checkout', LN(1 + efekt), 0))) AS mnoznik_checkout,
          ARRAY_AGG(IF(etap = 'karta', STRUCT(slot AS klucz, wariant AS wartosc), NULL) IGNORE NULLS) AS karta,
          ARRAY_AGG(IF(etap = 'checkout', STRUCT(slot AS klucz, wariant AS wartosc), NULL) IGNORE NULLS) AS checkout
        FROM warianty_wizyt
        GROUP BY n
      ) AS w
        USING (n)
    ),

    zdarzenia AS (
      -- ab_assign tylko przy pierwszej wizycie (tag losuje, gdy nie ma cookie); powracający wchodzą
      -- do testu przez parametr slotu na view_item / begin_checkout
      SELECT s.id_uzytkownika, s.start_wizyty AS czas, 'ab_assign' AS nazwa,
        [STRUCT('ab_test' AS klucz, k.klucz AS wartosc), ('ab_variant', k.wartosc)] AS parametry
      FROM sciezki AS s, UNNEST(s.karta) AS k
      WHERE s.czy_nowy
      UNION ALL
      SELECT id_uzytkownika, TIMESTAMP_ADD(start_wizyty, INTERVAL 5 SECOND), 'view_item',
        karta
      FROM sciezki
      UNION ALL
      SELECT s.id_uzytkownika, TIMESTAMP_ADD(s.start_wizyty, INTERVAL 119 SECOND), 'ab_assign',
        [STRUCT('ab_test' AS klucz, c.klucz AS wartosc), ('ab_variant', c.wartosc)]
      FROM sciezki AS s, UNNEST(s.checkout) AS c
      WHERE s.czy_nowy AND s.czy_koszyk
      UNION ALL
      SELECT id_uzytkownika, TIMESTAMP_ADD(start_wizyty, INTERVAL 120 SECOND), 'begin_checkout',
        ARRAY_CONCAT(karta, checkout)
      FROM sciezki
      WHERE czy_koszyk
      UNION ALL
      -- purchase z parametrami slotów jak każdy event; staging bierze wariant z ekspozycji
      SELECT id_uzytkownika, TIMESTAMP_ADD(start_wizyty, INTERVAL 300 SECOND), 'purchase',
        ARRAY_CONCAT(karta, checkout)
      FROM sciezki
      WHERE czy_koszyk AND czy_zakup_z_koszyka
    )

    -- kolumny i typy jak w eksporcie GA4; float_value w eksporcie nieużywane, ale jest w schemacie
    SELECT
      FORMAT_DATE('%Y%m%d', dzien) AS event_date,
      UNIX_MICROS(czas) AS event_timestamp,
      nazwa AS event_name,
      ARRAY(
        SELECT AS STRUCT
          p.klucz AS key,
          STRUCT(p.wartosc AS string_value, CAST(NULL AS INT64) AS int_value,
            CAST(NULL AS FLOAT64) AS float_value, CAST(NULL AS FLOAT64) AS double_value) AS value
        FROM UNNEST(parametry) AS p
      ) AS event_params,
      id_uzytkownika AS user_pseudo_id
    FROM zdarzenia;

    EXECUTE IMMEDIATE FORMAT('CREATE OR REPLACE TABLE `%s.%s.events_%s` AS SELECT * FROM zdarzenia_dnia',
      projekt_docelowy, zbior_docelowy, FORMAT_DATE('%Y%m%d', dzien));
  END IF;
  SET dzien = DATE_ADD(dzien, INTERVAL 1 DAY);
END WHILE;

/*
 Przykład: events_20260908 (pierwszy wiersz to nowy użytkownik, drugi powracający z 2026-09-01)
 event_date | event_timestamp  | event_name     | event_params                                    | user_pseudo_id
 20260908   | 1788861600000000 | ab_assign      | [ab_test: ab2, ab_variant: v1]                  | 1482736401.1788825600
 20260908   | 1788861605000000 | view_item      | [ab2: v1]                                       | 1482736401.1788825600
 20260908   | 1788864012000000 | view_item      | [ab2: v0]                                       | 1730021954.1788220800
 20260908   | 1788864127000000 | begin_checkout | [ab2: v0]                                       | 1730021954.1788220800
 20260908   | 1788864307000000 | purchase       | [ab2: v0]                                       | 1730021954.1788220800

 Oczekiwany fct_wyniki_testow_ab po dbt build na danych 2026-08-24 – 2026-11-04 (domyślne
 parametry, bez usterek; liczby z symulacji tej samej logiki — FARM_FINGERPRINT da inne, ale
 bliskie): CR wariantu / CR kontroli ≈ 1 + efekt, rozrzut ok. ±5 pp w ab2 i ab3, większy w ab4 i ab5,
 które dopiero ruszyły. ab1 (A/A): CR v1 ≈ CR v0, wynik nieistotny. Liczby ab2–ab3 policzono
 przed dodaniem ab1 — powracający z okna A/A mogą je lekko przesunąć.
 id_testu     | wariant | uzytkownicy | konwertujacy | CR     | prawda
 ab2_20260907 | v0      | 116829      | 4056         | 3,47%  | kontrola
 ab2_20260907 | v1      | 116854      | 4655         | 3,98%  | +10%
 ab3_20261005 | v0      | 78293       | 2801         | 3,58%  | kontrola
 ab3_20261005 | v1      | 77646       | 2746         | 3,54%  | 0%
 ab3_20261005 | v2      | 77837       | 3002         | 3,86%  | +12%
*/
