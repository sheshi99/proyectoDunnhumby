-- Migración única para quien ya cargó datos en public (flujo anterior).
-- Mueve las tablas sin copiar filas, índices ni restricciones (ALTER TABLE ... SET SCHEMA).
-- Ejecutar cada bloque conectado a su base. Si la base es nueva, no hace falta.
-- Antes: detener el job de pgAgent. Después: volver a ejecutar los scripts
-- staging_roles_permisos.sql / warehouse_roles_permisos.sql para asignar permisos.

-- ============ BLOQUE 1: conectado a dunnhumby_etl ============
BEGIN;
CREATE SCHEMA IF NOT EXISTS raw;
ALTER TABLE public.campaign_desc    SET SCHEMA raw;
ALTER TABLE public.campaign_table   SET SCHEMA raw;
ALTER TABLE public.causal_data      SET SCHEMA raw;
ALTER TABLE public.coupon           SET SCHEMA raw;
ALTER TABLE public.coupon_redempt   SET SCHEMA raw;
ALTER TABLE public.hh_demographic   SET SCHEMA raw;
ALTER TABLE public.product          SET SCHEMA raw;
ALTER TABLE public.transaction_data SET SCHEMA raw;
COMMIT;

-- ============ BLOQUE 2: conectado a Data_warehouse ============
-- Las claves foráneas de fact_sales y los IDs (identity) se conservan.
BEGIN;
CREATE SCHEMA IF NOT EXISTS dw;
ALTER TABLE public.dim_product             SET SCHEMA dw;
ALTER TABLE public.dim_household           SET SCHEMA dw;
ALTER TABLE public.dim_time                SET SCHEMA dw;
ALTER TABLE public.dim_promotional_context SET SCHEMA dw;
ALTER TABLE public.fact_sales              SET SCHEMA dw;
COMMIT;
