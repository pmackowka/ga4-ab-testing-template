/*
 GENERATOR · syntetyczny eksport GA4 dla projektu dbt
 Tworzy tabele dzienne events_RRRRMMDD (tylko kolumny czytane przez stg_ga4__zdarzenia)
 ze scenariuszem testów z dbt/seeds/rejestr_testow.csv. Wizyta = view_item → begin_checkout
 → purchase. Losowość z FARM_FINGERPRINT: ten sam dzień generuje się zawsze tak samo.
 Uruchom z lokalizacją danych EU (Ustawienia zapytania). Bez zmian nadrabia dni od ostatniej
 tabeli do wczoraj; podane data_od podmienia dni od niego.

 Parametry:
 - zbior_docelowy = vars.ga4_zbior_danych, data_startu = vars.ga4_data_startu w dbt
 - data_od: NULL = dzień po ostatniej tabeli events_ w zbiorze
 - udzial_powracajacych < 0,8: wizyty osób z poprzednich 28 dni
 - cr_koszyka: view_item → begin_checkout, cr_zakupu: begin_checkout → purchase
 - koszyk_mediana, koszyk_sigma: wartość zamówienia (zł), rozkład logarytmiczno-normalny
 - udzial_utraty_ciasteczka_testu: tag losuje ponownie 7 dni po przydziale
 - udzial_utraty_ga: nowy user_pseudo_id 7 dni po pierwszej wizycie, ciasteczko testu zostaje
 - ziarno: inne zachowanie tych samych użytkowników
 - testy: kopia seeda + efekt wariantu (względna zmiana CR); kontrola pierwsza, efekt 0; ab1 = A/A;
   etap 'karta' zmienia przejście do checkoutu, 'checkout' przejście do zakupu
 - usterka_srm_slot → sprawdz_srm (warn); usterka_brak_dnia → sprawdz_komplet_dni_ga4 (error)
*/

DECLARE projekt_docelowy STRING DEFAULT 'twoj-projekt';
DECLARE zbior_docelowy STRING DEFAULT 'ga4_syntetyczny';
DECLARE data_startu DATE DEFAULT DATE '2026-08-24';
DECLARE data_od DATE DEFAULT NULL;
DECLARE data_do DATE DEFAULT DATE_SUB(CURRENT_DATE(), INTERVAL 1 DAY);
DECLARE wizyty_dziennie INT64 DEFAULT 10000;
DECLARE udzial_powracajacych FLOAT64 DEFAULT 0.3;
DECLARE cr_koszyka FLOAT64 DEFAULT 0.10;
DECLARE cr_zakupu FLOAT64 DEFAULT 0.30;
DECLARE koszyk_mediana FLOAT64 DEFAULT 200;
DECLARE koszyk_sigma FLOAT64 DEFAULT 0.8;
DECLARE udzial_utraty_ciasteczka_testu FLOAT64 DEFAULT 0.10;
DECLARE udzial_utraty_ga FLOAT64 DEFAULT 0.10;
DECLARE ziarno STRING DEFAULT 'a';
DECLARE testy ARRAY<STRUCT<slot STRING, start_testu DATE, koniec_testu DATE, warianty ARRAY<STRING>,
  efekty ARRAY<FLOAT64>, etap STRING>> DEFAULT [
  ('ab1', DATE '2026-08-24', DATE '2026-09-06', ['v0', 'v1'], [0.0, 0.0], 'karta'),
  ('ab2', DATE '2026-09-07', DATE '2026-10-04', ['v0', 'v1'], [0.0, 0.10], 'karta'),
  ('ab3', DATE '2026-10-05', DATE '2026-11-01', ['v0', 'v1', 'v2'], [0.0, 0.0, 0.12], 'karta'),
  ('ab4', DATE '2026-11-02', DATE '2026-12-13', ['v0', 'v1'], [0.0, -0.05], 'karta'),
  ('ab5', DATE '2026-11-02', DATE '2026-11-29', ['v0', 'v1'], [0.0, 0.10], 'checkout')
];
DECLARE usterka_srm_slot STRING DEFAULT NULL;
DECLARE usterka_srm_udzial_kontroli FLOAT64 DEFAULT 0.53;
DECLARE usterka_brak_dnia DATE DEFAULT NULL;

DECLARE dzien DATE;
DECLARE liczba_nowych INT64 DEFAULT CAST(ROUND(wizyty_dziennie * (1 - udzial_powracajacych)) AS INT64);

ASSERT NOT EXISTS (SELECT 1 FROM UNNEST(testy) AS t WHERE ARRAY_LENGTH(t.efekty) != ARRAY_LENGTH(t.warianty))
  AS 'każdy test musi mieć tyle efektów, ile wariantów';
ASSERT udzial_powracajacych < 0.8
  AS 'udzial_powracajacych musi być < 0.8';

CREATE TEMP FUNCTION los(klucz STRING) AS (MOD(ABS(FARM_FINGERPRINT(klucz)), 1000000) / 1000000);
CREATE TEMP FUNCTION nr_z_liczby(b FLOAT64, udzial_kontroli FLOAT64, liczba INT64) AS (
  IF(b < udzial_kontroli, 0,
    1 + LEAST(liczba - 2, CAST(FLOOR((b - udzial_kontroli) / (1 - udzial_kontroli) * (liczba - 1)) AS INT64))));
CREATE TEMP FUNCTION nr_wariantu(id_ga STRING, slot STRING, start_testu DATE, czy_po_ponownym BOOL,
  udzial_kontroli FLOAT64, liczba INT64) AS (
  nr_z_liczby(los(FORMAT('w|%s|%s|%t%s', id_ga, slot, start_testu, IF(czy_po_ponownym, '|r', ''))),
    udzial_kontroli, liczba));

EXECUTE IMMEDIATE FORMAT("CREATE SCHEMA IF NOT EXISTS `%s.%s` OPTIONS (location = 'EU')",
  projekt_docelowy, zbior_docelowy);

IF data_od IS NULL THEN
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
    CREATE OR REPLACE TEMP TABLE wizyty_dnia AS
    WITH uzytkownicy AS (
      SELECT
        f AS dzien_pierwszej_wizyty,
        CONCAT(
          CAST(1000000000 + MOD(ABS(FARM_FINGERPRINT(FORMAT('u|%t|%d', f, nr))), 1000000000) AS STRING),
          '.', CAST(UNIX_SECONDS(TIMESTAMP(f)) AS STRING)) AS id_ga
      FROM UNNEST(GENERATE_DATE_ARRAY(DATE_SUB(dzien, INTERVAL 28 DAY), dzien)) AS f
      CROSS JOIN UNNEST(GENERATE_ARRAY(0, liczba_nowych - 1)) AS nr
    ),

    plan_wizyt AS (
      SELECT id_ga, dzien_pierwszej_wizyty, dzien_pierwszej_wizyty AS dzien_wizyty
      FROM uzytkownicy
      UNION DISTINCT
      SELECT
        u.id_ga,
        u.dzien_pierwszej_wizyty,
        DATE_ADD(u.dzien_pierwszej_wizyty, INTERVAL 1 + CAST(FLOOR(los(FORMAT('lag|%s|%d', u.id_ga, j)) * 28) AS INT64) DAY)
      FROM uzytkownicy AS u
      CROSS JOIN UNNEST(GENERATE_ARRAY(0, 3)) AS j
      WHERE los(FORMAT('pow|%s|%d', u.id_ga, j)) < udzial_powracajacych / (1 - udzial_powracajacych) / 4
    )

    SELECT
      *,
      IF(dzien_wizyty >= dzien_utraty_ga,
        CONCAT(CAST(1000000000 + MOD(ABS(FARM_FINGERPRINT(FORMAT('g|%s', id_ga))), 1000000000) AS STRING),
          '.', CAST(UNIX_SECONDS(TIMESTAMP(dzien_utraty_ga)) AS STRING)),
        id_ga) AS id_uzytkownika
    FROM (
      SELECT
        *,
        IF(los(FORMAT('ga|%s', id_ga)) < udzial_utraty_ga,
          MIN(IF(dzien_wizyty >= DATE_ADD(dzien_pierwszej_wizyty, INTERVAL 7 DAY), dzien_wizyty, NULL))
            OVER (PARTITION BY id_ga),
          NULL) AS dzien_utraty_ga
      FROM plan_wizyt
      WHERE dzien_wizyty <= dzien
        AND id_ga IN (SELECT id_ga FROM plan_wizyt WHERE dzien_wizyty = dzien)
    );

    CREATE OR REPLACE TEMP TABLE zdarzenia_dnia AS
    WITH testy_wizyt AS (
      SELECT
        w.id_ga,
        w.dzien_wizyty,
        t.slot,
        t.start_testu,
        t.etap,
        t.warianty,
        t.efekty,
        IF(t.slot = usterka_srm_slot, usterka_srm_udzial_kontroli, 1 / ARRAY_LENGTH(t.warianty)) AS udzial_kontroli,
        los(FORMAT('utrata|%s|%s|%t', w.id_ga, t.slot, t.start_testu)) < udzial_utraty_ciasteczka_testu AS czy_traci_ciasteczko
      FROM wizyty_dnia AS w
      JOIN UNNEST(testy) AS t
        ON w.dzien_wizyty BETWEEN t.start_testu AND t.koniec_testu
    ),

    karta_przydzialy AS (
      SELECT
        *,
        IF(czy_traci_ciasteczko,
          MIN(IF(dzien_wizyty >= DATE_ADD(dzien_przydzialu, INTERVAL 7 DAY), dzien_wizyty, NULL))
            OVER (PARTITION BY id_ga, slot, start_testu),
          NULL) AS dzien_ponownego_przydzialu
      FROM (
        SELECT *, MIN(dzien_wizyty) OVER (PARTITION BY id_ga, slot, start_testu) AS dzien_przydzialu
        FROM testy_wizyt
        WHERE etap = 'karta'
      )
    ),

    karta_warianty AS (
      SELECT
        id_ga,
        dzien_wizyty,
        EXP(SUM(LN(1 + efekty[OFFSET(nr)]))) AS mnoznik_karta,
        ARRAY_AGG(STRUCT(slot AS klucz, warianty[OFFSET(nr)] AS wartosc)) AS karta,
        ARRAY_AGG(IF(czy_przydzial, STRUCT(slot AS klucz, warianty[OFFSET(nr)] AS wartosc), NULL) IGNORE NULLS)
          AS karta_przydzial
      FROM (
        SELECT
          *,
          nr_wariantu(id_ga, slot, start_testu, IFNULL(dzien_wizyty >= dzien_ponownego_przydzialu, FALSE),
            udzial_kontroli, ARRAY_LENGTH(warianty)) AS nr,
          dzien_wizyty = dzien_przydzialu OR IFNULL(dzien_wizyty = dzien_ponownego_przydzialu, FALSE) AS czy_przydzial
        FROM karta_przydzialy
      )
      GROUP BY id_ga, dzien_wizyty
    ),

    koszyki AS (
      SELECT
        w.*,
        IFNULL(k.karta, []) AS karta,
        IFNULL(k.karta_przydzial, []) AS karta_przydzial,
        los(FORMAT('k|%s|%t', w.id_ga, w.dzien_wizyty)) < cr_koszyka * IFNULL(k.mnoznik_karta, 1) AS czy_koszyk
      FROM wizyty_dnia AS w
      LEFT JOIN karta_warianty AS k
        USING (id_ga, dzien_wizyty)
    ),

    checkout_przydzialy AS (
      SELECT
        *,
        IF(czy_traci_ciasteczko,
          MIN(IF(dzien_wizyty >= DATE_ADD(dzien_przydzialu, INTERVAL 7 DAY), dzien_wizyty, NULL))
            OVER (PARTITION BY id_ga, slot, start_testu),
          NULL) AS dzien_ponownego_przydzialu
      FROM (
        SELECT t.*, MIN(t.dzien_wizyty) OVER (PARTITION BY t.id_ga, t.slot, t.start_testu) AS dzien_przydzialu
        FROM testy_wizyt AS t
        JOIN koszyki AS k
          USING (id_ga, dzien_wizyty)
        WHERE t.etap = 'checkout'
          AND k.czy_koszyk
      )
    ),

    checkout_warianty AS (
      SELECT
        id_ga,
        dzien_wizyty,
        EXP(SUM(LN(1 + efekty[OFFSET(nr)]))) AS mnoznik_checkout,
        ARRAY_AGG(STRUCT(slot AS klucz, warianty[OFFSET(nr)] AS wartosc)) AS checkout,
        ARRAY_AGG(IF(czy_przydzial, STRUCT(slot AS klucz, warianty[OFFSET(nr)] AS wartosc), NULL) IGNORE NULLS)
          AS checkout_przydzial
      FROM (
        SELECT
          *,
          nr_wariantu(id_ga, slot, start_testu, IFNULL(dzien_wizyty >= dzien_ponownego_przydzialu, FALSE),
            udzial_kontroli, ARRAY_LENGTH(warianty)) AS nr,
          dzien_wizyty = dzien_przydzialu OR IFNULL(dzien_wizyty = dzien_ponownego_przydzialu, FALSE) AS czy_przydzial
        FROM checkout_przydzialy
      )
      GROUP BY id_ga, dzien_wizyty
    ),

    sciezki AS (
      SELECT
        k.*,
        IFNULL(c.checkout, []) AS checkout,
        IFNULL(c.checkout_przydzial, []) AS checkout_przydzial,
        los(FORMAT('%s|z|%s|%t', ziarno, k.id_ga, k.dzien_wizyty)) < cr_zakupu * IFNULL(c.mnoznik_checkout, 1) AS czy_zakup_z_koszyka,
        TIMESTAMP_ADD(TIMESTAMP(dzien), INTERVAL CAST(FLOOR(los(FORMAT('%s|t|%s|%t', ziarno, k.id_ga, dzien)) * 82800) AS INT64) SECOND)
          AS start_wizyty
      FROM koszyki AS k
      LEFT JOIN checkout_warianty AS c
        USING (id_ga, dzien_wizyty)
      WHERE k.dzien_wizyty = dzien
    ),

    zdarzenia AS (
      SELECT s.id_uzytkownika, s.start_wizyty AS czas, 'ab_assign' AS nazwa,
        [STRUCT('ab_test' AS klucz, k.klucz AS wartosc), ('ab_variant', k.wartosc)] AS parametry,
        CAST(NULL AS STRING) AS id_transakcji, CAST(NULL AS FLOAT64) AS przychod
      FROM sciezki AS s, UNNEST(s.karta_przydzial) AS k
      UNION ALL
      SELECT id_uzytkownika, TIMESTAMP_ADD(start_wizyty, INTERVAL 5 SECOND), 'view_item',
        karta, NULL, NULL
      FROM sciezki
      UNION ALL
      SELECT s.id_uzytkownika, TIMESTAMP_ADD(s.start_wizyty, INTERVAL 119 SECOND), 'ab_assign',
        [STRUCT('ab_test' AS klucz, c.klucz AS wartosc), ('ab_variant', c.wartosc)], NULL, NULL
      FROM sciezki AS s, UNNEST(s.checkout_przydzial) AS c
      UNION ALL
      SELECT id_uzytkownika, TIMESTAMP_ADD(start_wizyty, INTERVAL 120 SECOND), 'begin_checkout',
        ARRAY_CONCAT(karta, checkout), NULL, NULL
      FROM sciezki
      WHERE czy_koszyk
      UNION ALL
      SELECT id_uzytkownika, TIMESTAMP_ADD(start_wizyty, INTERVAL 300 SECOND), 'purchase',
        ARRAY_CONCAT(karta, checkout),
        CONCAT('T', CAST(MOD(ABS(FARM_FINGERPRINT(FORMAT('%s|tx|%s|%t', ziarno, id_ga, dzien))), 1000000000) AS STRING)),
        ROUND(koszyk_mediana * EXP(koszyk_sigma
          * SQRT(-2 * LN(1 - los(FORMAT('%s|r1|%s|%t', ziarno, id_ga, dzien))))
          * COS(2 * ACOS(-1) * los(FORMAT('%s|r2|%s|%t', ziarno, id_ga, dzien)))), 2)
      FROM sciezki
      WHERE czy_koszyk AND czy_zakup_z_koszyka
    )

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
      id_uzytkownika AS user_pseudo_id,
      STRUCT(id_transakcji AS transaction_id, przychod AS purchase_revenue) AS ecommerce
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
 które dopiero ruszyły. ab1 (A/A): CR v1 ≈ CR v0, wynik nieistotny. Kolumny jakości to ok. 0,5–1%
 użytkowników testu; ab4 i ab5 mają w nich 0, bo utrata ciasteczek zaczyna się 7 dni po przydziale.
 Przychód na użytkownika zmienia się jak CR (koszyk nie zależy od wariantu), ale jego względny
 rozrzut jest ok. 1,9× większy (1 + CV² koszyka), więc ten sam test daje szerszy zakres.
 id_testu     | wariant | uzytkownicy | konwertujacy | CR     | prawda   | przychod_na_uzytkownika | odchylenie_przychodu | wykluczeni_mieszani | ponownie_przydzieleni | bez_przydzialu
 ab2_20260907 | v0      | 118076      | 4129         | 3,50%  | kontrola | 9,69                    | 70,07                | 562                 | 1127                  | 1081
 ab2_20260907 | v1      | 117937      | 4587         | 3,89%  | +10%     | 10,67                   | 72,80                | 577                 | 1115                  | 983
 ab3_20261005 | v0      | 78115       | 2770         | 3,55%  | kontrola | 9,88                    | 72,06                | 467                 | 720                   | 655
 ab3_20261005 | v1      | 78718       | 2769         | 3,52%  | 0%       | 9,56                    | 67,69                | 503                 | 757                   | 667
 ab3_20261005 | v2      | 78925       | 3018         | 3,82%  | +12%     | 10,73                   | 74,30                | 471                 | 704                   | 691
*/
