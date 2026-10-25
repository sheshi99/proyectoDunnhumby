-- Ejecutar completo en pgAdmin, conectado a dunnhumby_etl.
-- Copia las ocho tablas de public sin modificar el origen.
-- No sobrescribe tablas ni vistas existentes en staging.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;

DO $$
DECLARE
    tabla text;
BEGIN
    IF current_database() <> 'dunnhumby_etl' THEN
        RAISE EXCEPTION 'Conectarse a dunnhumby_etl. Base actual: %', current_database();
    END IF;

    -- Verificar todo antes de empezar a copiar.
    FOREACH tabla IN ARRAY ARRAY['campaign_desc', 'campaign_table', 'causal_data',
        'coupon', 'coupon_redempt', 'hh_demographic', 'product', 'transaction_data']
    LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = tabla AND c.relkind IN ('r', 'p')
        ) THEN
            RAISE EXCEPTION 'Falta la tabla public.%. Ejecutar la carga original primero.', tabla;
        END IF;
        IF to_regclass(format('staging.%I', tabla)) IS NOT NULL THEN
            RAISE EXCEPTION 'Ya existe staging.%. No se sobrescribe; revisar antes de copiar.', tabla;
        END IF;
    END LOOP;
END $$;

CREATE SCHEMA IF NOT EXISTS staging;

DO $$
DECLARE
    tabla text;
    filas bigint;
BEGIN
    FOREACH tabla IN ARRAY ARRAY['campaign_desc', 'campaign_table', 'causal_data',
        'coupon', 'coupon_redempt', 'hh_demographic', 'product', 'transaction_data']
    LOOP
        EXECUTE format('CREATE TABLE staging.%I AS SELECT * FROM public.%I', tabla, tabla);
        GET DIAGNOSTICS filas = ROW_COUNT;
        RAISE NOTICE 'Copiada public.% a staging.%: % filas', tabla, tabla, filas;
    END LOOP;
END $$;

COMMIT;
