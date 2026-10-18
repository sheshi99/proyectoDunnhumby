-- ============================================================
-- EVALUACIÓN DE CALIDAD DE DATOS: COUPON_REDEMPT
-- Proyecto: Data Warehouse Dunnhumby
-- Tabla: public.coupon_redempt
-- Las consultas son de solo lectura.
-- ============================================================

-- Cantidad total de registros analizados
SELECT COUNT(*) AS total_registros
FROM public.coupon_redempt;

-- 1. IDENTIFICACIÓN DE VALORES NULOS
SELECT
    COUNT(*) AS total_registros,
    COUNT(*) FILTER (WHERE household_key IS NULL) AS hogares_nulos,
    COUNT(*) FILTER (WHERE "DAY" IS NULL) AS dias_nulos,
    COUNT(*) FILTER (WHERE "COUPON_UPC" IS NULL) AS cupon_upc_nulos,
    COUNT(*) FILTER (WHERE "CAMPAIGN" IS NULL) AS campanas_nulas
FROM public.coupon_redempt;

-- 2. IDENTIFICACIÓN DE REGISTROS DUPLICADOS
-- Se evalúan filas exactamente idénticas en todas sus columnas
SELECT
    (SELECT COUNT(*) FROM public.coupon_redempt) AS total_registros,
    COUNT(*) AS registros_unicos,
    (SELECT COUNT(*) FROM public.coupon_redempt) - COUNT(*) AS registros_duplicados
FROM (SELECT DISTINCT * FROM public.coupon_redempt) AS datos_unicos;

-- 3. IDENTIFICACIÓN DE VALORES NEGATIVOS O CERO
SELECT
    COUNT(*) FILTER (WHERE household_key <= 0) AS hogares_invalidos,
    COUNT(*) FILTER (WHERE "DAY" <= 0) AS dias_invalidos,
    COUNT(*) FILTER (WHERE "COUPON_UPC" <= 0) AS cupones_invalidos,
    COUNT(*) FILTER (WHERE "CAMPAIGN" <= 0) AS campanas_invalidas
FROM public.coupon_redempt;

-- 4. INTEGRIDAD REFERENCIAL Y CORRESPONDENCIA ENTRE TABLAS

-- 4.1. Correspondencia de cupones con la tabla COUPON 
-- Verifica que cada cupón usado por un cliente exista en el catálogo oficial de cupones (tabla coupon).

SELECT
    COUNT(DISTINCT r."COUPON_UPC") AS cupones_redimidos_distintos,
    COUNT(DISTINCT r."COUPON_UPC") FILTER (WHERE c."COUPON_UPC" IS NULL) AS cupones_sin_maestro
FROM (SELECT DISTINCT "COUPON_UPC" FROM public.coupon_redempt) r
LEFT JOIN (SELECT DISTINCT "COUPON_UPC" FROM public.coupon) c
    ON r."COUPON_UPC" = c."COUPON_UPC";

-- 4.2. Correspondencia con CAMPAIGN_DESC
-- Confirma que los cupones canjeados pertenezcan a una campaña registrada en el maestro de campañas
-- (tabla campaign_desc).

SELECT
    COUNT(DISTINCT r."CAMPAIGN") AS campanas_distintas,
    COUNT(DISTINCT r."CAMPAIGN") FILTER (WHERE cd."CAMPAIGN" IS NULL) AS campanas_sin_maestro
FROM (SELECT DISTINCT "CAMPAIGN" FROM public.coupon_redempt) r
LEFT JOIN (SELECT DISTINCT "CAMPAIGN" FROM public.campaign_desc) cd
    ON r."CAMPAIGN" = cd."CAMPAIGN";

-- 4.3. Cobertura demográfica de los hogares redentores
-- Identifica cuántos hogares que usaron cupones tienen información de perfil registrada en la tabla hh_demographic.

SELECT
    COUNT(DISTINCT r.household_key) AS hogares_redentores_distintos,
    COUNT(DISTINCT r.household_key) FILTER (WHERE h.household_key IS NOT NULL) AS hogares_con_demografia,
    COUNT(DISTINCT r.household_key) FILTER (WHERE h.household_key IS NULL) AS hogares_sin_demografia
FROM (SELECT DISTINCT household_key FROM public.coupon_redempt) r
LEFT JOIN (SELECT DISTINCT household_key FROM public.hh_demographic) h
    ON r.household_key = h.household_key;


-- ============================================================
-- RELACIONES TABLA: coupon_redempt
-- ------------------------------------------------------------
-- -> Relación con: coupon
--    - Tipo: N a 1
--    - Llave de unión: COUPON_UPC
--    - Propósito: Muestra los detalles del cupón que fue utilizado.
--
-- -> Relación con: campaign_desc
--    - Tipo: N a 1
--    - Llave de unión: CAMPAIGN
--    - Propósito: Indica a cuál campaña pertenece el cupón que se redimió.
--
-- -> Relación con: hh_demographic
--    - Tipo: N a 1
--    - Llave de unión: household_key
--    - Propósito: Conecta al hogar que usó el cupón con su información demográfica.
-- ============================================================


-- ============================================================
-- 5. CONCLUSIONES Y DECISIONES PARA EL ETL: COUPON_REDEMPT
-- ============================================================
-- RESULTADOS:
-- - Se analizaron todas las filas de la tabla transaccional de redenciones.
-- - No se registraron valores nulos en columnas criticas (household_key, 
--   DAY, COUPON_UPC, CAMPAIGN).
-- - No se encontraron identificadores ni dias con valores negativos o 
--   iguales a cero (<= 0).
-- - Integridad referencial con COUPON: 556 cupones redimidos distintos, 
--   100% presentes en la tabla maestra (0 cupones sin maestro).
-- - Integridad referencial con CAMPAIGN_DESC: 30 campañas distintas asociadas 
--   a redenciones, 100% presentes en el catalogo (0 campañas huerfanas).
-- - Cobertura demografica: De 434 hogares redentores unicos, 311 cuentan 
--   con perfil en hh_demographic y 123 no tienen correspondencia.
--
-- DECISIONES PARA EL ETL Y EL DATA WAREHOUSE:
-- - Modelar coupon_redempt como Tabla de Hechos de Evento de Redencion 
--   (fct_coupon_redemption).
-- - No eliminar transacciones de los 123 hogares sin cobertura demografica. 
--   En dbt se vincularan a la dimension demografica usando un valor por 
--   defecto ('Desconocido / No registrado' o clave -1) para preservar el 
--   volumen real de redenciones.
-- - Conservar la relacion compuesta entre cupón y campaña para garantizar 
--   la trazabilidad promocional.
--
-- CONCLUSION FINAL:
-- La evaluacion de calidad de coupon_redempt confirma la consistencia a nivel 
-- transaccional y referencial con los maestros principales. La cobertura parcial 
-- demografica se gestionara en dbt mediante reglas de sustitucion controladas, 
-- dejando el dataset listo para el modelo dimensional.