-- Ejecutar TODO el archivo en Query Tool de pgAdmin, en dunnhumby_etl.
-- Conectarse como postgres u otro administrador con permisos equivalentes.
-- Usa automáticamente el usuario conectado: no hay nombres que reemplazar.
-- Puede repetirse; no elimina esquemas, tablas, vistas ni roles existentes.
-- Si la sesión tiene una transacción abortada, ejecutar ROLLBACK por separado.

BEGIN;

DO $$
BEGIN
    IF current_database() <> 'dunnhumby_etl' THEN
        RAISE EXCEPTION 'Conectarse a dunnhumby_etl. Base actual: %', current_database();
    END IF;
END $$;

-- Verificar la base de datos y el usuario actual
SELECT
    current_database() AS base_datos,
    current_user AS usuario_actual;
	
-- Crear el esquema para Staging
CREATE SCHEMA IF NOT EXISTS staging;

-- Crear el esquema para el Data Warehouse
-- Corrección del error: «no existe el esquema data_warehouse».
-- Antes se creaba data_werehouse (error de escritura), mientras que los
-- GRANT usaban data_warehouse. PostgreSQL los considera esquemas distintos.
-- Se unifica el nombre como data_warehouse en la creación y los permisos.
-- El esquema anterior no se elimina ni se modifican sus objetos.
CREATE SCHEMA IF NOT EXISTS data_warehouse;

-- Verificar los esquemas de trabajo
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('staging', 'data_warehouse')
ORDER BY schema_name;

-- Crear los roles solo si no existen, para poder repetir el script.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_staging') THEN
        CREATE ROLE rol_staging NOLOGIN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'rol_data_warehouse') THEN
        CREATE ROLE rol_data_warehouse NOLOGIN;
    END IF;
END $$;

---------------------------------------------------------
-- NOLOGIN significa que son roles para asignar permisos, 
-- no usuarios que inician sesión directamente.
---------------------------------------------------------


-- ==========================================
-- CONFIGURACIÓN DE PERMISOS
-- EN LOS ROLES CREADOS
-- ==========================================

-- 1. Permisos para trabajar en Staging
GRANT USAGE, CREATE ON SCHEMA staging
TO rol_staging;

-- Permisos sobre las tablas existentes en Staging
GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA staging
TO rol_staging;


-- 2. Permisos para consultar el Data Warehouse
GRANT USAGE ON SCHEMA data_warehouse
TO rol_data_warehouse;

-- Permisos de lectura sobre las tablas existentes
GRANT SELECT
ON ALL TABLES IN SCHEMA data_warehouse
TO rol_data_warehouse;

-- Permisos futuros para objetos creados por el usuario conectado.
-- Si otro usuario (por ejemplo dbt) crea objetos, sus permisos predeterminados
-- deben configurarse también para ese usuario.
ALTER DEFAULT PRIVILEGES
IN SCHEMA staging
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLES TO rol_staging;

-- Permisos para las futuras tablas del Data Warehouse
ALTER DEFAULT PRIVILEGES
IN SCHEMA data_warehouse
GRANT SELECT
ON TABLES TO rol_data_warehouse;

-- Asignar ambos roles al usuario conectado, sin nombres fijos.
DO $$
BEGIN
    EXECUTE format('GRANT rol_staging, rol_data_warehouse TO %I', current_user);
END $$;


-- Verificar los roles asignados al usuario
SELECT
    r.rolname AS rol_asignado
FROM pg_roles r
JOIN pg_auth_members m
    ON r.oid = m.roleid
JOIN pg_roles u
    ON u.oid = m.member
WHERE u.rolname = current_user
  AND r.rolname IN (
      'rol_staging',
      'rol_data_warehouse'
  );

-- Ambos permisos deben devolver true.
SELECT
    has_schema_privilege('rol_staging', 'staging', 'USAGE')
        AND has_schema_privilege('rol_staging', 'staging', 'CREATE')
        AS permisos_staging,
    has_schema_privilege('rol_data_warehouse', 'data_warehouse', 'USAGE')
        AS permiso_data_warehouse;

COMMIT;
  
  
/*
==========================================================
 CONFIGURACIÓN DE POSTGRESQL - PROYECTO DUNNHUMBY
==========================================================
Se configuraron los esquemas de trabajo staging y
data_warehouse dentro de la base de datos dunnhumby_etl.

El esquema staging se utilizará para preparar, limpiar
y transformar los datos provenientes de las ocho tablas
originales de Dunnhumby.

El esquema data_warehouse almacenará el modelo dimensional
de estrella, compuesto por cuatro dimensiones y una tabla
de hechos (fact_ventas).

Además, se crearon los roles rol_staging y
rol_data_warehouse para controlar el acceso a los esquemas.

Se asignaron los permisos correspondientes y se configuraron
permisos predeterminados para las futuras tablas.

Esta configuración prepara la base de datos para las
siguientes etapas del proceso ETL y la construcción
del Data Warehouse, sin modificar las tablas originales.
==========================================================
*/