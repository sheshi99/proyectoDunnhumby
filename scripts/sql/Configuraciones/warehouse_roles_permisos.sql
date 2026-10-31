
BEGIN;

-- Verificar que la configuración se aplique a la base de datos del warehouse.
DO $$ BEGIN
    IF current_database() <> 'Data_warehouse' THEN
        RAISE EXCEPTION 'Conectarse a Data_warehouse';
    END IF;
END $$;

-- Verificar la base de datos y el usuario actual.
SELECT current_database() AS base_datos, current_user AS usuario_actual;

-- Las dimensiones y hechos se materializan en el esquema public existente.
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'public';

-- Crear el rol solo si no existe, para poder repetir el script.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_data_warehouse') THEN
        CREATE ROLE rol_data_warehouse NOLOGIN;
    END IF;
END $$;

---------------------------------------------------------
-- NOLOGIN significa que es un rol para asignar permisos,
-- no un usuario que inicia sesión directamente.
---------------------------------------------------------

-- ==========================================
-- CONFIGURACIÓN DE PERMISOS DEL WAREHOUSE
-- ==========================================

-- Permitir la conexión a la base del warehouse.
GRANT CONNECT ON DATABASE "Data_warehouse" TO rol_data_warehouse;

-- Permitir usar el esquema que contiene las dimensiones y hechos.
GRANT USAGE ON SCHEMA public TO rol_data_warehouse;

-- Permisos de lectura sobre las tablas existentes.
GRANT SELECT ON ALL TABLES IN SCHEMA public TO rol_data_warehouse;

-- Permisos futuros para tablas creadas por el usuario conectado.
-- Si otro usuario crea las tablas dbt, configurar también sus permisos predeterminados.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT ON TABLES TO rol_data_warehouse;

-- Asignar el rol al usuario conectado, sin nombres fijos.
DO $$ BEGIN
    EXECUTE format('GRANT rol_data_warehouse TO %I', current_user);
END $$;
-- Verificar el rol asignado al usuario actual.
SELECT r.rolname AS rol_asignado
FROM pg_roles r
JOIN pg_auth_members m ON r.oid = m.roleid
JOIN pg_roles u ON u.oid = m.member
WHERE u.rolname = current_user AND r.rolname = 'rol_data_warehouse';

-- Los dos resultados deben devolver true.
SELECT
    has_database_privilege('rol_data_warehouse', current_database(), 'CONNECT') AS permiso_conexion,
    has_schema_privilege('rol_data_warehouse', 'public', 'USAGE') AS permiso_warehouse;

COMMIT;

/*
==========================================================
 CONFIGURACIÓN DEL WAREHOUSE - PROYECTO DUNNHUMBY
==========================================================
La base Data_warehouse almacena el modelo dimensional de
estrella en public: cuatro dimensiones y la tabla fact_sales.
Los modelos dbt crean estas tablas a partir de las vistas
limpias de dunnhumby_etl.staging.

El rol rol_data_warehouse permite consultar las tablas finales.
Se asignan permisos sobre las tablas existentes y permisos
predeterminados para las futuras tablas creadas por el usuario
conectado. El usuario de ejecución dbt debe contar además con
los permisos necesarios para crear y reconstruir las tablas.

Los roles son globales al servidor PostgreSQL; los permisos de
este archivo se aplican a Data_warehouse y su esquema public.
La configuración de staging se ejecuta por separado en
dunnhumby_etl con staging_roles_permisos.sql.

Este archivo configura permisos; no crea dimensiones, hechos
ni un esquema staging en la base del warehouse.
==========================================================
*/
