-- Ejecutar completo en dunnhumby_etl, despu?s de 00_validar_requisitos.sql.
-- Conserva las filas y valores originales; solo define nombres y tipos.
BEGIN;
DO $$
BEGIN
    IF current_database() <> 'dunnhumby_etl' THEN
        RAISE EXCEPTION 'Conectarse a dunnhumby_etl. Base actual: %', current_database();
    END IF;
END $$;

CREATE OR REPLACE VIEW staging.transaction_data AS
SELECT household_key::bigint AS household_key, "BASKET_ID"::bigint AS basket_id,
       "DAY"::bigint AS day, "PRODUCT_ID"::bigint AS product_id,
       "QUANTITY"::bigint AS quantity, "SALES_VALUE"::numeric AS sales_value,
       "STORE_ID"::bigint AS store_id, "RETAIL_DISC"::numeric AS retail_disc,
       "TRANS_TIME"::bigint AS trans_time, "WEEK_NO"::bigint AS week_no,
       "COUPON_DISC"::numeric AS coupon_disc, "COUPON_MATCH_DISC"::numeric AS coupon_match_disc
FROM public.transaction_data;

GRANT USAGE ON SCHEMA staging TO rol_staging;
GRANT SELECT ON staging.transaction_data TO rol_staging;
COMMIT;
