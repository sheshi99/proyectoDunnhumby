
BEGIN;

-- Verificar que la configuración se aplique a la base de trabajo. (Staging)
DO $$ BEGIN
    IF current_database() <> 'dunnhumby_etl' THEN
        RAISE EXCEPTION 'Conectarse a dunnhumby_etl';
    END IF;
END $$;

-- Verificar la base de datos y el usuario actual.
SELECT current_database() AS base_datos, current_user AS usuario_actual;

-- Crear el esquema de trabajo sin modificar los originales en public.
CREATE SCHEMA IF NOT EXISTS staging;

SELECT schema_name
FROM information_schema.schemata
WHERE schema_name = 'staging';

-- Crear el rol solo si no existe, para poder repetir el script.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_staging') THEN
        CREATE ROLE rol_staging NOLOGIN;
    END IF;
END $$;

---------------------------------------------------------
-- NOLOGIN significa que es un rol para asignar permisos,
-- no un usuario que inicia sesión directamente.
---------------------------------------------------------

-- ==========================================
-- CONFIGURACIÓN DE PERMISOS DE STAGING
-- ==========================================

-- Permitir la conexión a la base de trabajo.
GRANT CONNECT ON DATABASE dunnhumby_etl TO rol_staging;

-- Permisos para usar staging y crear objetos de trabajo.
GRANT USAGE, CREATE ON SCHEMA staging TO rol_staging;

-- Permisos sobre las tablas y vistas existentes en staging.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA staging TO rol_staging;

-- Permisos futuros para objetos creados por el usuario conectado.
-- Si otro usuario crea objetos dbt, configurar también sus permisos predeterminados.
ALTER DEFAULT PRIVILEGES IN SCHEMA staging
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO rol_staging;

-- Asignar el rol al usuario conectado, sin nombres fijos.
DO $$ BEGIN
    EXECUTE format('GRANT rol_staging TO %I', current_user);
END $$;
-- Verificar el rol asignado al usuario actual.
SELECT r.rolname AS rol_asignado
FROM pg_roles r
JOIN pg_auth_members m ON r.oid = m.roleid
JOIN pg_roles u ON u.oid = m.member
WHERE u.rolname = current_user AND r.rolname = 'rol_staging';


COMMIT;

/*
==========================================================
 CONFIGURACIÓN DE STAGING - PROYECTO DUNNHUMBY
==========================================================
La base dunnhumby_etl conserva los datos originales en public.
El esquema staging contiene las copias de trabajo y las vistas
limpias que preparan los datos provenientes de las ocho tablas
originales de Dunnhumby.

El rol rol_staging permite trabajar en este esquema. Se asignan
permisos sobre los objetos existentes y permisos predeterminados
para los futuros objetos creados por el usuario conectado.

Los roles son globales al servidor PostgreSQL; los permisos de
este archivo se aplican a dunnhumby_etl y su esquema staging.
La configuración del warehouse se ejecuta por separado en la
base Data_warehouse con warehouse_roles_permisos.sql.

Esta configuración prepara la base de trabajo para el ETL
sin modificar las tablas originales de public.
==========================================================
*/
