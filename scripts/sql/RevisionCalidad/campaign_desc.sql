
-- ============================================================
-- EVALUACIÓN DE CALIDAD DE DATOS: CAMPAIGN_DESC
-- Proyecto: Data Warehouse Dunnhumby
-- Tabla: public.campaign_desc
-- Las consultas son de solo lectura.
-- ============================================================


--- Observar la información de la tabla 

SELECT * FROM public.campaign_desc;

-- Cantidad total de registros analizados
SELECT COUNT(*) AS total_registros
FROM public.campaign_desc; 

-- 1. IDENTIFICACIÓN DE VALORES NULOS Y VACÍOS
SELECT
    COUNT(*) AS total_registros,
    COUNT(*) FILTER (WHERE "CAMPAIGN" IS NULL) AS campana_nula,
    COUNT(*) FILTER (WHERE "DESCRIPTION" IS NULL) AS descripcion_nula,
    COUNT(*) FILTER (WHERE TRIM("DESCRIPTION") = '') AS descripcion_vacia,
    COUNT(*) FILTER (WHERE "START_DAY" IS NULL) AS dia_inicio_nulo,
    COUNT(*) FILTER (WHERE "END_DAY" IS NULL) AS dia_fin_nulo
FROM public.campaign_desc;

-- 2. IDENTIFICACIÓN DE REGISTROS DUPLICADOS
-- Se valida la unicidad de la llave primaria CAMPAIGN
SELECT
    COUNT(*) AS total_registros,
    COUNT(DISTINCT "CAMPAIGN") AS campanas_unicas,
    COUNT(*) - COUNT(DISTINCT "CAMPAIGN") AS campanas_duplicadas
FROM public.campaign_desc;

-- 3. IDENTIFICACIÓN DE VALORES NEGATIVOS O INCONSISTENCIAS LÓGICAS
SELECT
    COUNT(*) FILTER (WHERE "CAMPAIGN" <= 0) AS campana_invalida,
    COUNT(*) FILTER (WHERE "START_DAY" < 0) AS dia_inicio_negativo,
    COUNT(*) FILTER (WHERE "END_DAY" < 0) AS dia_fin_negativo,
    COUNT(*) FILTER (WHERE "START_DAY" > "END_DAY") AS inicio_mayor_que_fin
FROM public.campaign_desc;


-- 4. VERIFICACIÓN DE INTEGRIDAD CON CAMPAIGN_TABLE
-- Verifica cuántas campañas del maestro (tabla campaign_desc) tienen hogares 
-- asignados en la tabla campaign_table.
SELECT
    COUNT(DISTINCT cd."CAMPAIGN") AS campanas_en_desc,
    COUNT(DISTINCT ct."CAMPAIGN") FILTER (WHERE ct."CAMPAIGN" IS NOT NULL) AS campanas_con_hogares_asignados
FROM public.campaign_desc cd
LEFT JOIN public.campaign_table ct ON cd."CAMPAIGN" = ct."CAMPAIGN";


-- ============================================================
-- RELACIONES TABLA: campaign_desc
-- ------------------------------------------------------------
-- -> Relación con: campaign_table
--    - Tipo: 1 a N
--    - Llave de unión: CAMPAIGN
--    - Propósito: Identifica cuáles hogares participaron en cada campaña.
-- ============================================================


-- ============================================================
-- 5. CONCLUSIÓN Y CONSIDERACIONES PARA EL ETL: CAMPAIGN_DESC
-- ============================================================
-- RESULTADOS:
-- - Se analizaron 30 registros correspondientes al 100% de la tabla.
-- - No se identificaron valores nulos ni cadenas vacías en CAMPAIGN, 
--   DESCRIPTION, START_DAY ni END_DAY.
-- - Se confirmó la unicidad de la clave primaria CAMPAIGN (30 campañas 
--   únicas, 0 duplicados).
-- - No se encontraron valores negativos ni inconsistencias cronológicas 
--   (START_DAY es estrictamente menor o igual a END_DAY en el 100% de los casos).
-- - La integridad referencial con campaign_table es del 100% (30 de 30 
--   campañas tienen hogares asignados, 0 campañas huérfanas).
--
-- DECISIONES Y CONSIDERACIONES PARA EL ETL:
-- - CAMPAIGN se conserva en staging para relacionar campañas con hogares,
--   cupones y vigencias que alimentan los indicadores de contexto promocional.
-- - Se asegurará el formato estandarizado del texto en DESCRIPTION para 
--   categorizar los tipos de campaña (TypeA, TypeB, TypeC) en dbt.
-- - START_DAY y END_DAY permiten identificar los días de vigencia de las
--   campañas asignadas. El modelo actual no materializa una dimensión de campañas.
--
-- CONCLUSIÓN FINAL:
-- La tabla campaign_desc presenta una calidad de datos óptima y sin anomalías. 
-- La ausencia de nulos y duplicados, sumada a su perfecta integridad referencial, 
-- permite cerrar su evaluación e integrar la entidad con total seguridad al modelo dimensional.

