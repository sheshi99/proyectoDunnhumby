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

GRANT USAGE ON SCHEMA staging TO rol_staging;
COMMIT;
