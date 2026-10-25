-- Ejecutar completo en dunnhumby_etl, despu?s de 00_validar_requisitos.sql.
-- Conserva las filas y valores originales; solo define nombres y tipos.
BEGIN;
DO $$
BEGIN
    IF current_database() <> 'dunnhumby_etl' THEN
        RAISE EXCEPTION 'Conectarse a dunnhumby_etl. Base actual: %', current_database();
    END IF;
END $$;

CREATE OR REPLACE VIEW staging.causal_data AS
SELECT "PRODUCT_ID"::bigint AS product_id, "STORE_ID"::bigint AS store_id,
       "WEEK_NO"::bigint AS week_no, display::text AS display, mailer::text AS mailer
FROM public.causal_data;

GRANT USAGE ON SCHEMA staging TO rol_staging;
GRANT SELECT ON staging.causal_data TO rol_staging;
COMMIT;
