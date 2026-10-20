-- ===========================================================================
-- EVALUACIÓN DE CALIDAD: CAMPAIGN_TABLE
-- Ejecutar cada consulta por separado en PostgreSQL (base dunnhumby_etl).
-- Solo lectura: estas consultas no modifican los datos.
-- Cada fila asocia un hogar con una campaña. No demuestra un canje o compra.
-- Un hogar puede estar en varias campañas y una campaña incluir varios hogares.
-- ===========================================================================

-- 1. Vista previa y conteos generales.
SELECT * FROM public.campaign_table LIMIT 10;

SELECT COUNT(*) AS total_asignaciones,
       COUNT(DISTINCT household_key) AS hogares_distintos,
       COUNT(DISTINCT "CAMPAIGN") AS campanas_distintas
FROM public.campaign_table;

-- 2. Nulos y descripciones vacías.
SELECT COUNT(*) FILTER (WHERE household_key IS NULL) AS hogares_nulos,
       COUNT(*) FILTER (WHERE "CAMPAIGN" IS NULL) AS campanas_nulas,
       COUNT(*) FILTER (WHERE "DESCRIPTION" IS NULL) AS descripciones_nulas,
       COUNT(*) FILTER (WHERE BTRIM("DESCRIPTION") = '') AS descripciones_vacias
FROM public.campaign_table;

-- 3. Repeticiones de la combinación hogar-campaña.
-- Repetir solo household_key o solo CAMPAIGN es normal en esta tabla.
SELECT household_key, "CAMPAIGN", COUNT(*) AS apariciones
FROM public.campaign_table
GROUP BY household_key, "CAMPAIGN"
HAVING COUNT(*) > 1;

SELECT (SELECT COUNT(*) FROM public.campaign_table) - COUNT(*)
       AS filas_duplicadas_exactas
FROM (SELECT DISTINCT * FROM public.campaign_table) AS asignaciones;

-- 4. Identificadores no positivos y tipos de campaña observados.
SELECT COUNT(*) FILTER (WHERE household_key <= 0) AS hogares_no_positivos,
       COUNT(*) FILTER (WHERE "CAMPAIGN" <= 0) AS campanas_no_positivas
FROM public.campaign_table;

SELECT "DESCRIPTION", COUNT(*) AS total_asignaciones
FROM public.campaign_table
GROUP BY "DESCRIPTION"
ORDER BY total_asignaciones DESC;

-- 5. Cobertura demográfica de los hogares asignados.
-- La ausencia de perfil demográfico no demuestra un hogar inválido.
-- Se cuentan hogares distintos, no filas de asignaciones.
SELECT COUNT(*) AS hogares_distintos,
       COUNT(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM public.hh_demographic h
           WHERE h.household_key = c.household_key
       )) AS con_demografia,
       COUNT(*) FILTER (WHERE NOT EXISTS (
           SELECT 1 FROM public.hh_demographic h
           WHERE h.household_key = c.household_key
       )) AS sin_demografia
FROM (SELECT DISTINCT household_key FROM public.campaign_table
      WHERE household_key IS NOT NULL) c;

-- Muestra de hogares sin perfil para investigar.
SELECT DISTINCT c.household_key
FROM public.campaign_table c
WHERE c.household_key IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.hh_demographic h
      WHERE h.household_key = c.household_key
  )
ORDER BY c.household_key
LIMIT 20;

-- 6. Campañas sin correspondencia en el catálogo campaign_desc.
SELECT DISTINCT c."CAMPAIGN"
FROM public.campaign_table c
WHERE c."CAMPAIGN" IS NOT NULL
  AND NOT EXISTS (
      SELECT 1 FROM public.campaign_desc d
      WHERE d."CAMPAIGN" = c."CAMPAIGN"
  )
ORDER BY c."CAMPAIGN";

-- Descripciones diferentes para una misma campaña entre ambas tablas.
-- Solo compara campañas que existen en el catálogo; incluye diferencias NULL.
SELECT c."CAMPAIGN", c."DESCRIPTION" AS descripcion_asignacion,
       d."DESCRIPTION" AS descripcion_catalogo, COUNT(*) AS filas
FROM public.campaign_table c
JOIN public.campaign_desc d ON d."CAMPAIGN" = c."CAMPAIGN"
WHERE c."DESCRIPTION" IS DISTINCT FROM d."DESCRIPTION"
GROUP BY c."CAMPAIGN", c."DESCRIPTION", d."DESCRIPTION";

-- 7. Resumen de hogares asignados por campaña.
SELECT "CAMPAIGN", COUNT(*) AS asignaciones,
       COUNT(DISTINCT household_key) AS hogares_distintos
FROM public.campaign_table
GROUP BY "CAMPAIGN"
ORDER BY "CAMPAIGN";

-- ============================================================
-- CONCLUSIONES Y CONSIDERACIONES PARA EL ETL: CAMPAIGN_TABLE
-- Resultados verificados en PostgreSQL mediante las consultas ejecutadas
-- y las capturas de resultados compartidas durante la revisión.
-- ============================================================
-- RESULTADOS:
-- - Se analizaron 7.208 asignaciones correspondientes a 1.584 hogares
--   distintos y 30 campañas distintas.
-- - No se encontraron valores nulos en household_key, CAMPAIGN ni
--   DESCRIPTION, ni descripciones vacías o compuestas solo por espacios.
-- - No se encontraron combinaciones household_key-CAMPAIGN repetidas;
--   por tanto, tampoco existen filas completamente duplicadas.
-- - No se encontraron identificadores de hogar o campaña iguales a cero
--   o negativos.
-- - Las 30 campañas tienen correspondencia en CAMPAIGN_DESC y las
--   descripciones coinciden entre ambas tablas.
-- - De los 1.584 hogares asignados, 760 tienen perfil en HH_DEMOGRAPHIC
--   y 824 no tienen correspondencia demográfica.
--
-- CONSIDERACIONES PARA EL ETL:
-- - Mantener una fila por combinación hogar-campaña y validar su unicidad
--   en futuras cargas. Un hogar puede estar asignado a varias campañas.
-- - Conservar todas las asignaciones, incluidas las de los 824 hogares
--   sin perfil demográfico. La ausencia de perfil no demuestra un error.
-- - Usar LEFT JOIN desde CAMPAIGN_TABLE al incorporar datos demográficos
--   para evitar perder asignaciones; identificar los atributos ausentes
--   como información no registrada según las reglas del modelo destino.
-- - Mantener controles de correspondencia con CAMPAIGN_DESC y coherencia
--   de las descripciones.
-- - Interpretar estas filas como asignaciones a campañas; por sí solas
--   no acreditan compras ni canjes de cupones.
--
-- CONCLUSIÓN FINAL:
-- Las comprobaciones realizadas no identificaron nulos, descripciones
-- vacías, duplicados ni identificadores no positivos. La correspondencia
-- con el catálogo de campañas es completa. La cobertura demográfica es
-- parcial y debe gestionarse conservando las asignaciones originales.