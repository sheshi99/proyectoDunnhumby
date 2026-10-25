-- Solo lectura. Una excepción impide considerar aceptada la capa.
-- Se evalúan todas las columnas para forzar la conversión de todos los datos.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;
DO $$
DECLARE
    tabla text;
    origen bigint;
    destino bigint;
    columnas text;
    evaluados bigint;
BEGIN
    IF current_database() <> 'dunnhumby_etl' THEN
        RAISE EXCEPTION 'Conectarse a dunnhumby_etl. Base actual: %', current_database();
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'staging') THEN
        RAISE EXCEPTION 'Falta staging. Ejecutar configuración y 00_validar_requisitos.sql y dbt run primero.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_staging') THEN
        RAISE EXCEPTION 'Falta el rol rol_staging';
    END IF;
    IF NOT has_schema_privilege('rol_staging', 'staging', 'USAGE') THEN
        RAISE EXCEPTION 'rol_staging no tiene USAGE en staging';
    END IF;
    -- Solo las dos vistas de dbt implementadas actualmente.
    FOREACH tabla IN ARRAY ARRAY['causal_data', 'transaction_data']
    LOOP
        IF NOT EXISTS (SELECT 1 FROM information_schema.views
                       WHERE table_schema = 'staging' AND table_name = 'stg_' || tabla) THEN
            RAISE EXCEPTION 'Falta la vista staging.stg_%', tabla;
        END IF;
        IF NOT has_table_privilege('rol_staging', format('staging.%I', 'stg_' || tabla), 'SELECT') THEN
            RAISE EXCEPTION 'rol_staging no tiene SELECT en staging.stg_%', tabla;
        END IF;
        EXECUTE format('SELECT count(*) FROM staging.%I', tabla) INTO origen;
        EXECUTE format('SELECT count(*) FROM staging.%I', 'stg_' || tabla) INTO destino;
        IF origen <> destino THEN
            RAISE EXCEPTION 'Conteo diferente en %: tabla=%, vista=%', tabla, origen, destino;
        END IF;
        IF origen = 0 THEN
            RAISE EXCEPTION 'Fuente vacía: staging.%', tabla;
        END IF;
        SELECT string_agg(format('count(%I)', column_name), ' + ' ORDER BY ordinal_position)
        INTO columnas FROM information_schema.columns
        WHERE table_schema = 'staging' AND table_name = 'stg_' || tabla;
        EXECUTE format('SELECT %s FROM staging.%I', columnas, 'stg_' || tabla) INTO evaluados;
        RAISE NOTICE 'OK staging.%: % filas; SELECT para rol_staging; conversiones evaluadas (% valores no nulos)',
                     tabla, destino, evaluados;
    END LOOP;
END $$;

SELECT table_name, column_name, data_type, ordinal_position
FROM information_schema.columns
WHERE table_schema = 'staging'
ORDER BY table_name, ordinal_position;
COMMIT;