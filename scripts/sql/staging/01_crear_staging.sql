-- Ejecutar en dunnhumby_etl después de scripts/cargar_bd.py.
-- Las vistas conservan todas las filas, nulos, signos y etiquetas originales.
-- Las conversiones fallan ante tipos incompatibles; no se descartan registros.
BEGIN;
-- Primero ejecutar completo Configuraciones/esquema_roles_permisos.sql.
-- No se crean roles ni se asigna un usuario fijo desde este script.
DO $$
DECLARE
    tabla text;
BEGIN
    IF current_database() <> 'dunnhumby_etl' THEN
        RAISE EXCEPTION 'Conectarse a dunnhumby_etl. Base actual: %', current_database();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_staging') THEN
        RAISE EXCEPTION 'Falta rol_staging. Ejecutar primero la configuración de esquemas y permisos.';
    END IF;
    FOREACH tabla IN ARRAY ARRAY['campaign_desc', 'campaign_table', 'causal_data',
        'coupon', 'coupon_redempt', 'hh_demographic', 'product', 'transaction_data']
    LOOP
        IF to_regclass(format('public.%I', tabla)) IS NULL THEN
            RAISE EXCEPTION 'Falta public.%. Cargar las ocho fuentes antes de crear staging.', tabla;
        END IF;
    END LOOP;
END $$;
CREATE SCHEMA IF NOT EXISTS staging;
COMMENT ON SCHEMA staging IS 'Fuentes Dunnhumby tipadas para consumo de dbt; origen public.';

CREATE OR REPLACE VIEW staging.campaign_desc AS
SELECT "DESCRIPTION"::text AS description, "CAMPAIGN"::bigint AS campaign,
       "START_DAY"::bigint AS start_day, "END_DAY"::bigint AS end_day
FROM public.campaign_desc;

CREATE OR REPLACE VIEW staging.campaign_table AS
SELECT "DESCRIPTION"::text AS description, household_key::bigint AS household_key,
       "CAMPAIGN"::bigint AS campaign
FROM public.campaign_table;

CREATE OR REPLACE VIEW staging.causal_data AS
SELECT "PRODUCT_ID"::bigint AS product_id, "STORE_ID"::bigint AS store_id,
       "WEEK_NO"::bigint AS week_no, display::text AS display, mailer::text AS mailer
FROM public.causal_data;

CREATE OR REPLACE VIEW staging.coupon AS
SELECT "COUPON_UPC"::bigint AS coupon_upc, "PRODUCT_ID"::bigint AS product_id,
       "CAMPAIGN"::bigint AS campaign
FROM public.coupon;

CREATE OR REPLACE VIEW staging.coupon_redempt AS
SELECT household_key::bigint AS household_key, "DAY"::bigint AS day,
       "COUPON_UPC"::bigint AS coupon_upc, "CAMPAIGN"::bigint AS campaign
FROM public.coupon_redempt;

CREATE OR REPLACE VIEW staging.hh_demographic AS
SELECT "AGE_DESC"::text AS age_desc, "MARITAL_STATUS_CODE"::text AS marital_status_code,
       "INCOME_DESC"::text AS income_desc, "HOMEOWNER_DESC"::text AS homeowner_desc,
       "HH_COMP_DESC"::text AS hh_comp_desc, "HOUSEHOLD_SIZE_DESC"::text AS household_size_desc,
       "KID_CATEGORY_DESC"::text AS kid_category_desc, household_key::bigint AS household_key
FROM public.hh_demographic;

CREATE OR REPLACE VIEW staging.product AS
SELECT "PRODUCT_ID"::bigint AS product_id, "MANUFACTURER"::bigint AS manufacturer,
       "DEPARTMENT"::text AS department, "BRAND"::text AS brand,
       "COMMODITY_DESC"::text AS commodity_desc, "SUB_COMMODITY_DESC"::text AS sub_commodity_desc,
       "CURR_SIZE_OF_PRODUCT"::text AS curr_size_of_product
FROM public.product;

CREATE OR REPLACE VIEW staging.transaction_data AS
SELECT household_key::bigint AS household_key, "BASKET_ID"::bigint AS basket_id,
       "DAY"::bigint AS day, "PRODUCT_ID"::bigint AS product_id,
       "QUANTITY"::bigint AS quantity, "SALES_VALUE"::numeric AS sales_value,
       "STORE_ID"::bigint AS store_id, "RETAIL_DISC"::numeric AS retail_disc,
       "TRANS_TIME"::bigint AS trans_time, "WEEK_NO"::bigint AS week_no,
       "COUPON_DISC"::numeric AS coupon_disc, "COUPON_MATCH_DISC"::numeric AS coupon_match_disc
FROM public.transaction_data;

-- Permisos explícitos, independientemente del usuario que cree las vistas.
GRANT USAGE ON SCHEMA staging TO rol_staging;
GRANT SELECT ON staging.campaign_desc, staging.campaign_table, staging.causal_data,
    staging.coupon, staging.coupon_redempt, staging.hh_demographic,
    staging.product, staging.transaction_data TO rol_staging;
COMMIT;