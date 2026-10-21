-- Verificar la base de datos y el usuario actual
SELECT
    current_database() AS base_datos,
    current_user AS usuario_actual;
	
-- Crear el esquema para Staging
CREATE SCHEMA IF NOT EXISTS staging;

-- Crear el esquema para el Data Warehouse
CREATE SCHEMA IF NOT EXISTS data_werehouse;

-- Verificar los esquemas de trabajo
SELECT schema_name
FROM information_schema.schemata
WHERE schema_name IN ('staging', 'data_warehouse')
ORDER BY schema_name;

-- Crear rol para la capa Staging
CREATE ROLE rol_staging NOLOGIN;

-- Crear rol para la capa Data Warehouse
CREATE ROLE rol_data_warehouse NOLOGIN;

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

-- Permisos para las futuras tablas de Staging
ALTER DEFAULT PRIVILEGES FOR ROLE walbyn -- Cambiar por el usuario que estan trabajando
IN SCHEMA staging
GRANT SELECT, INSERT, UPDATE, DELETE
ON TABLES TO rol_staging;

-- Permisos para las futuras tablas del Data Warehouse
ALTER DEFAULT PRIVILEGES FOR ROLE walbyn -- Cambiar por el usuario que estan trabajando
IN SCHEMA data_warehouse
GRANT SELECT
ON TABLES TO rol_data_warehouse;

-- Asignar el rol de Staging al usuario correspondiente
GRANT rol_staging TO walbyn;

-- Asignar el rol del Data Warehouse al usuario correspondiente
GRANT rol_data_warehouse TO walbyn;


-- Verificar los roles asignados al usuario
SELECT
    r.rolname AS rol_asignado
FROM pg_roles r
JOIN pg_auth_members m
    ON r.oid = m.roleid
JOIN pg_roles u
    ON u.oid = m.member
WHERE u.rolname = 'walbyn'
  AND r.rolname IN (
      'rol_staging',
      'rol_data_warehouse'
  );
  
  
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
