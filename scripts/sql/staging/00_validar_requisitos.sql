-- Ejecutar en dunnhumby_etl despues de copiar_tablas_a_staging.sql.
-- Las vistas conservan todas las filas, nulos, signos y etiquetas originales.
-- Las conversiones fallan ante tipos incompatibles; no se descartan registros.
BEGIN;
CREATE SCHEMA IF NOT EXISTS staging;
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
        IF NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'staging' AND c.relname = tabla AND c.relkind IN ('r', 'p')) THEN
            RAISE EXCEPTION 'Falta la tabla original staging.%. Ejecutar primero copiar_tablas_a_staging.sql.', tabla;
        END IF;
    END LOOP;
END $$;
COMMENT ON SCHEMA staging IS 'Tablas originales Dunnhumby y vistas stg_ preparadas por dbt.';

GRANT USAGE, CREATE ON SCHEMA staging TO rol_staging;
GRANT SELECT ON ALL TABLES IN SCHEMA staging TO rol_staging;
COMMIT;
