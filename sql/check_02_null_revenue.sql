CREATE SCHEMA IF NOT EXISTS `ab-test-sandbox.check_sql02` OPTIONS (location = 'EU');

FOR day IN (SELECT d FROM UNNEST(GENERATE_DATE_ARRAY('2026-08-31', '2026-09-06')) AS d)
DO
  EXECUTE IMMEDIATE FORMAT("""
    CREATE OR REPLACE TABLE `ab-test-sandbox.check_sql02.events_%s` AS
    SELECT
      '%s' AS event_date,
      event_timestamp,
      event_name,
      'u1' AS user_pseudo_id,
      STRUCT(transaction_id, purchase_revenue) AS ecommerce
    FROM UNNEST([
      STRUCT(1 AS event_timestamp, 'view_item' AS event_name,
        CAST(NULL AS STRING) AS transaction_id, CAST(NULL AS FLOAT64) AS purchase_revenue),
      (2, 'purchase', 'T1', NULL),
      (3, 'purchase', 'T1', 100)
    ])
    WHERE '%s' = '20260831' OR event_name = 'view_item'
  """, FORMAT_DATE('%Y%m%d', day.d), FORMAT_DATE('%Y%m%d', day.d), FORMAT_DATE('%Y%m%d', day.d));
END FOR;
