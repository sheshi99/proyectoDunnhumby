-- ===========================================================================
-- EVALUACIÓN DE CALIDAD: HH_DEMOGRAPHIC
-- Ejecutar cada consulta por separado en PostgreSQL (base dunnhumby_etl).
-- Solo lectura: estas consultas no modifican los datos.
-- Cada fila describe un hogar; household_key es su identificador candidato.
-- ===========================================================================

-- 1. Conocer las columnas y contar filas y hogares distintos.
SELECT * FROM public.hh_demographic LIMIT 10;

SELECT COUNT(*) AS total_registros,
       COUNT(DISTINCT household_key) AS hogares_distintos
FROM public.hh_demographic;

-- 2. Nulos, textos vacíos y categorías por revisar en cada columna.
-- Unknown y None/Unknown son categorías originales: no equivalen a NULL.
-- No reemplazarlas ni eliminarlas sin conocer su definición.
SELECT v.columna,
       COUNT(*) FILTER (WHERE v.valor IS NULL) AS nulos,
       COUNT(*) FILTER (WHERE BTRIM(v.valor) = '') AS vacios,
       COUNT(*) FILTER (
           WHERE LOWER(BTRIM(v.valor)) IN ('unknown', 'none/unknown')
       ) AS categorias_desconocidas
FROM public.hh_demographic h
CROSS JOIN LATERAL (VALUES
    ('household_key', h.household_key::text),
    ('AGE_DESC', h."AGE_DESC"::text),
    ('MARITAL_STATUS_CODE', h."MARITAL_STATUS_CODE"::text),
    ('INCOME_DESC', h."INCOME_DESC"::text),
    ('HOMEOWNER_DESC', h."HOMEOWNER_DESC"::text),
    ('HH_COMP_DESC', h."HH_COMP_DESC"::text),
    ('HOUSEHOLD_SIZE_DESC', h."HOUSEHOLD_SIZE_DESC"::text),
    ('KID_CATEGORY_DESC', h."KID_CATEGORY_DESC"::text)
) AS v(columna, valor)
GROUP BY v.columna
ORDER BY v.columna;

-- 3. Hogares repetidos: se espera una fila por household_key.
-- Si no devuelve filas, no hay identificadores no nulos repetidos.
SELECT household_key, COUNT(*) AS apariciones
FROM public.hh_demographic
WHERE household_key IS NOT NULL
GROUP BY household_key
HAVING COUNT(*) > 1;

-- Duplicados exactos: distinguirlos de hogares con perfiles diferentes.
SELECT (SELECT COUNT(*) FROM public.hh_demographic) - COUNT(*)
       AS filas_duplicadas_exactas
FROM (SELECT DISTINCT * FROM public.hh_demographic) AS perfiles;

-- 4. Identificadores no positivos: investigar si existen.
SELECT COUNT(*) FILTER (WHERE household_key <= 0) AS hogares_no_positivos
FROM public.hh_demographic;

-- 5. Categorías y frecuencias para revisar consistencia.
-- Los rangos de edad/ingreso y valores como '5+' son categorías de texto.
-- Los códigos (por ejemplo, estado civil) requieren el diccionario de datos.
SELECT v.columna, v.valor, COUNT(*) AS frecuencia
FROM public.hh_demographic h
CROSS JOIN LATERAL (VALUES
    ('AGE_DESC', h."AGE_DESC"::text),
    ('MARITAL_STATUS_CODE', h."MARITAL_STATUS_CODE"::text),
    ('INCOME_DESC', h."INCOME_DESC"::text),
    ('HOMEOWNER_DESC', h."HOMEOWNER_DESC"::text),
    ('HH_COMP_DESC', h."HH_COMP_DESC"::text),
    ('HOUSEHOLD_SIZE_DESC', h."HOUSEHOLD_SIZE_DESC"::text),
    ('KID_CATEGORY_DESC', h."KID_CATEGORY_DESC"::text)
) AS v(columna, valor)
GROUP BY v.columna, v.valor
ORDER BY v.columna, frecuencia DESC, v.valor;

-- 6. Hogares con y sin participación registrada en campañas.
-- EXISTS evita multiplicar hogares que participaron en varias campañas.
SELECT COUNT(*) AS hogares_con_perfil,
       COUNT(*) FILTER (WHERE EXISTS (
           SELECT 1 FROM public.campaign_table c
           WHERE c.household_key = h.household_key
       )) AS con_campanas,
       COUNT(*) FILTER (WHERE NOT EXISTS (
           SELECT 1 FROM public.campaign_table c
           WHERE c.household_key = h.household_key
       )) AS sin_campanas
FROM (SELECT DISTINCT household_key FROM public.hh_demographic
      WHERE household_key IS NOT NULL) h;

-- ============================================================
-- CONCLUSIONES Y CONSIDERACIONES PARA EL ETL: HH_DEMOGRAPHIC
-- Resultados verificados en PostgreSQL mediante las consultas ejecutadas
-- y las capturas de resultados compartidas durante la revisión.
-- ============================================================
-- RESULTADOS:
-- - Se analizaron 801 registros correspondientes a 801 hogares únicos.
-- - household_key no presenta valores nulos ni repetidos; por tanto,
--   tampoco existen filas completamente duplicadas.
-- - No se encontraron valores nulos en las ocho columnas ni textos
--   vacíos o compuestos únicamente por espacios en las columnas de texto.
-- - No se encontraron identificadores de hogar iguales a cero o negativos.
-- - HOMEOWNER_DESC contiene 233 hogares con la categoría 'Unknown'.
-- - HH_COMP_DESC contiene 73 hogares con la categoría 'Unknown'.
--   Se conservará el valor original durante el ETL.
-- - KID_CATEGORY_DESC contiene 558 hogares con 'None/Unknown'. Esta
--   categoría no permite distinguir ausencia de niños de dato desconocido.
-- - De los 801 hogares con perfil, 760 tienen asignaciones registradas
--   en CAMPAIGN_TABLE y 41 no tienen asignaciones registradas.
--
-- CONSIDERACIONES PARA EL ETL:
-- - Usar household_key como identificador de origen del hogar, manteniendo
--   controles de unicidad y ausencia de nulos en futuras cargas.
-- - Conservar las categorías originales, incluyendo 'Unknown' y
--   'None/Unknown'; no sustituirlas por valores supuestos.
-- - Consultar el diccionario de datos antes de interpretar o recodificar
--   categorías demográficas. Los rangos se mantienen como texto.
-- - Conservar los 41 perfiles sin campañas; esa ausencia no demuestra error.
--
-- CONCLUSIÓN FINAL:
-- Las comprobaciones realizadas no identificaron nulos, textos vacíos,
-- duplicados ni identificadores no positivos. Se documenta la presencia
-- de categorías desconocidas o ambiguas como una limitación del análisis
-- demográfico. Estos resultados no sustituyen la validación de categorías
-- contra el diccionario de datos.