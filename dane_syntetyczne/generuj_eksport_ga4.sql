DECLARE projekt_docelowy STRING DEFAULT 'ab-test-sandbox';
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
  ('ab2', DATE '2026-09-07', DATE '2026-09-20', ['v0', 'v1'], [0.0, 0.10], 'karta'),
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
      QUALIFY LOGICAL_OR(dzien_wizyty = dzien) OVER (PARTITION BY id_ga)
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
