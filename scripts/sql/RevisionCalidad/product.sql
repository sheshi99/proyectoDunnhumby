-- ============================================================
-- EVALUACIÓN DE CALIDAD DE DATOS: PRODUCT
-- Proyecto: Data Warehouse Dunnhumby
-- Tabla: public.product
-- Las consultas son de solo lectura; no modifican los datos.
-- ============================================================


-- 0. OBSERVACIÓN DE LA INFORMACIÓN
SELECT * FROM public.product;


-- 0.1. CANTIDAD TOTAL DE REGISTROS
SELECT COUNT(*) AS total_registros
FROM public.product;


-- 1. IDENTIFICACIÓN DE VALORES NULOS
-- Se revisan todas las columnas.
SELECT
    COUNT(*) AS total_registros,
    COUNT(*) FILTER (
        WHERE "PRODUCT_ID" IS NULL
    ) AS productos_nulos,
    COUNT(*) FILTER (
        WHERE "MANUFACTURER" IS NULL
    ) AS fabricantes_nulos,
    COUNT(*) FILTER (
        WHERE "DEPARTMENT" IS NULL
    ) AS departamentos_nulos,
    COUNT(*) FILTER (
        WHERE "BRAND" IS NULL
    ) AS marcas_nulas,
    COUNT(*) FILTER (
        WHERE "COMMODITY_DESC" IS NULL
    ) AS descripciones_nulas,
    COUNT(*) FILTER (
        WHERE "SUB_COMMODITY_DESC" IS NULL
    ) AS subdescripciones_nulas,
    COUNT(*) FILTER (
        WHERE "CURR_SIZE_OF_PRODUCT" IS NULL
    ) AS tamanos_nulos
FROM public.product;


-- 1.1. IDENTIFICACIÓN DE TEXTOS VACÍOS
-- Detecta cadenas vacías o compuestas únicamente por espacios.
SELECT
    COUNT(*) FILTER (
        WHERE TRIM("DEPARTMENT") = ''
    ) AS departamentos_vacios,
    COUNT(*) FILTER (
        WHERE TRIM("BRAND") = ''
    ) AS marcas_vacias,
    COUNT(*) FILTER (
        WHERE TRIM("COMMODITY_DESC") = ''
    ) AS descripciones_vacias,
    COUNT(*) FILTER (
        WHERE TRIM("SUB_COMMODITY_DESC") = ''
    ) AS subdescripciones_vacias,
    COUNT(*) FILTER (
        WHERE TRIM("CURR_SIZE_OF_PRODUCT") = ''
    ) AS tamanos_vacios
FROM public.product;


-- 2. IDENTIFICACIÓN DE REGISTROS DUPLICADOS
-- Se cuentan las filas completamente idénticas.
-- registros_duplicados indica las filas adicionales a las únicas.
SELECT
    (SELECT COUNT(*) FROM public.product) AS total_registros,
    COUNT(*) AS registros_unicos,
    (SELECT COUNT(*) FROM public.product)
        - COUNT(*) AS registros_duplicados
FROM (
    SELECT DISTINCT *
    FROM public.product
) AS datos_unicos;


-- 2.1. REVISIÓN DE UNICIDAD DE PRODUCT_ID
-- Detecta identificadores repetidos, aunque sus atributos difieran.
-- Si no devuelve filas, no hay PRODUCT_ID no nulos repetidos.
SELECT
    "PRODUCT_ID",
    COUNT(*) AS cantidad_registros
FROM public.product
WHERE "PRODUCT_ID" IS NOT NULL
GROUP BY "PRODUCT_ID"
HAVING COUNT(*) > 1
ORDER BY cantidad_registros DESC;


-- 3. IDENTIFICACIÓN DE VALORES NEGATIVOS Y CERO
-- Se revisan las dos columnas numéricas.
-- Los ceros se documentan y se interpretan según el significado
-- de los códigos; no se consideran errores automáticamente.
SELECT
    COUNT(*) FILTER (
        WHERE "PRODUCT_ID" < 0
    ) AS productos_negativos,
    COUNT(*) FILTER (
        WHERE "PRODUCT_ID" = 0
    ) AS productos_cero,
    COUNT(*) FILTER (
        WHERE "MANUFACTURER" < 0
    ) AS fabricantes_negativos,
    COUNT(*) FILTER (
        WHERE "MANUFACTURER" = 0
    ) AS fabricantes_cero
FROM public.product;


-- 4. VERIFICACIÓN DE INTEGRIDAD REFERENCIAL
-- Se comprueba que los productos no nulos utilizados en otras
-- tablas existan en PRODUCT.
-- DISTINCT evita multiplicar los conteos por registros repetidos.


-- 4.1. CORRESPONDENCIA CON TRANSACTION_DATA
SELECT
    COUNT(*) AS productos_distintos_en_transacciones,
    COUNT(*) FILTER (
        WHERE p."PRODUCT_ID" IS NOT NULL
    ) AS productos_con_correspondencia,
    COUNT(*) FILTER (
        WHERE p."PRODUCT_ID" IS NULL
    ) AS productos_sin_correspondencia
FROM (
    SELECT DISTINCT "PRODUCT_ID"
    FROM public.transaction_data
    WHERE "PRODUCT_ID" IS NOT NULL
) AS t
LEFT JOIN (
    SELECT DISTINCT "PRODUCT_ID"
    FROM public.product
    WHERE "PRODUCT_ID" IS NOT NULL
) AS p
    ON t."PRODUCT_ID" = p."PRODUCT_ID";


-- 4.2. CORRESPONDENCIA CON CAUSAL_DATA
SELECT
    COUNT(*) AS productos_distintos_en_causal,
    COUNT(*) FILTER (
        WHERE p."PRODUCT_ID" IS NOT NULL
    ) AS productos_con_correspondencia,
    COUNT(*) FILTER (
        WHERE p."PRODUCT_ID" IS NULL
    ) AS productos_sin_correspondencia
FROM (
    SELECT DISTINCT "PRODUCT_ID"
    FROM public.causal_data
    WHERE "PRODUCT_ID" IS NOT NULL
) AS c
LEFT JOIN (
    SELECT DISTINCT "PRODUCT_ID"
    FROM public.product
    WHERE "PRODUCT_ID" IS NOT NULL
) AS p
    ON c."PRODUCT_ID" = p."PRODUCT_ID";


-- 4.3. CORRESPONDENCIA CON COUPON
SELECT
    COUNT(*) AS productos_distintos_en_coupon,
    COUNT(*) FILTER (
        WHERE p."PRODUCT_ID" IS NOT NULL
    ) AS productos_con_correspondencia,
    COUNT(*) FILTER (
        WHERE p."PRODUCT_ID" IS NULL
    ) AS productos_sin_correspondencia
FROM (
    SELECT DISTINCT "PRODUCT_ID"
    FROM public.coupon
    WHERE "PRODUCT_ID" IS NOT NULL
) AS c
LEFT JOIN (
    SELECT DISTINCT "PRODUCT_ID"
    FROM public.product
    WHERE "PRODUCT_ID" IS NOT NULL
) AS p
    ON c."PRODUCT_ID" = p."PRODUCT_ID";


-- 5. IDENTIFICACIÓN DE VALORES INCONSISTENTES


-- 5.1. ESPACIOS AL INICIO O AL FINAL DE LOS TEXTOS
SELECT
    COUNT(*) FILTER (
        WHERE "DEPARTMENT" <> TRIM("DEPARTMENT")
    ) AS departamentos_con_espacios,
    COUNT(*) FILTER (
        WHERE "BRAND" <> TRIM("BRAND")
    ) AS marcas_con_espacios,
    COUNT(*) FILTER (
        WHERE "COMMODITY_DESC" <> TRIM("COMMODITY_DESC")
    ) AS descripciones_con_espacios,
    COUNT(*) FILTER (
        WHERE "SUB_COMMODITY_DESC" <> TRIM("SUB_COMMODITY_DESC")
    ) AS subdescripciones_con_espacios,
    COUNT(*) FILTER (
        WHERE "CURR_SIZE_OF_PRODUCT" <> TRIM("CURR_SIZE_OF_PRODUCT")
    ) AS tamanos_con_espacios
FROM public.product;


-- 5.2. REVISIÓN DE CATEGORÍAS DE MARCA
-- Se muestran los valores existentes y su frecuencia.
-- Una categoría no se considera incorrecta sin validar su significado.
SELECT
    "BRAND",
    COUNT(*) AS total_registros
FROM public.product
GROUP BY "BRAND"
ORDER BY total_registros DESC;


-- 5.3. DESCRIPCIONES NO DISPONIBLES
-- Estas etiquetas representan información no disponible,
-- aunque estén almacenadas como texto y no como NULL.
SELECT
    COUNT(*) FILTER (
        WHERE UPPER(TRIM("COMMODITY_DESC"))
            = 'NO COMMODITY DESCRIPTION'
    ) AS sin_descripcion,
    COUNT(*) FILTER (
        WHERE UPPER(TRIM("SUB_COMMODITY_DESC"))
            = 'NO SUBCOMMODITY DESCRIPTION'
    ) AS sin_subdescripcion
FROM public.product;


-- 5.4. DIFERENCIAS DE ESCRITURA EN LAS CATEGORÍAS
-- Identifica valores distintos que coinciden al quitar espacios
-- exteriores y convertirlos a mayúsculas.
-- Si no devuelve filas, no se detectaron variantes de este tipo.
SELECT
    'DEPARTMENT' AS columna,
    UPPER(TRIM("DEPARTMENT")) AS valor_normalizado,
    COUNT(DISTINCT "DEPARTMENT") AS cantidad_variantes,
    STRING_AGG(
        DISTINCT "DEPARTMENT", ' | '
    ) AS variantes
FROM public.product
WHERE TRIM("DEPARTMENT") <> ''
GROUP BY UPPER(TRIM("DEPARTMENT"))
HAVING COUNT(DISTINCT "DEPARTMENT") > 1

UNION ALL

SELECT
    'BRAND',
    UPPER(TRIM("BRAND")),
    COUNT(DISTINCT "BRAND"),
    STRING_AGG(DISTINCT "BRAND", ' | ')
FROM public.product
WHERE TRIM("BRAND") <> ''
GROUP BY UPPER(TRIM("BRAND"))
HAVING COUNT(DISTINCT "BRAND") > 1

UNION ALL

SELECT
    'COMMODITY_DESC',
    UPPER(TRIM("COMMODITY_DESC")),
    COUNT(DISTINCT "COMMODITY_DESC"),
    STRING_AGG(DISTINCT "COMMODITY_DESC", ' | ')
FROM public.product
WHERE TRIM("COMMODITY_DESC") <> ''
GROUP BY UPPER(TRIM("COMMODITY_DESC"))
HAVING COUNT(DISTINCT "COMMODITY_DESC") > 1

UNION ALL

SELECT
    'SUB_COMMODITY_DESC',
    UPPER(TRIM("SUB_COMMODITY_DESC")),
    COUNT(DISTINCT "SUB_COMMODITY_DESC"),
    STRING_AGG(DISTINCT "SUB_COMMODITY_DESC", ' | ')
FROM public.product
WHERE TRIM("SUB_COMMODITY_DESC") <> ''
GROUP BY UPPER(TRIM("SUB_COMMODITY_DESC"))
HAVING COUNT(DISTINCT "SUB_COMMODITY_DESC") > 1

ORDER BY columna, valor_normalizado;


-- ============================================================
-- RELACIONES TABLA: PRODUCT
-- ------------------------------------------------------------
-- -> TRANSACTION_DATA
--    Columna de unión: PRODUCT_ID.
--    Propósito: relacionar las ventas con los atributos del producto.
--
-- -> CAUSAL_DATA
--    Columna de unión: PRODUCT_ID.
--    Propósito: relacionar los productos con información promocional.
--
-- -> COUPON
--    Columna de unión: PRODUCT_ID.
--    Propósito: identificar los productos asociados a los cupones.
-- ============================================================
--
-- ============================================================
-- 6. RESULTADOS Y CONSIDERACIONES PARA EL ETL: PRODUCT
-- ============================================================
--
-- RESULTADOS:
-- - Se analizaron 92.353 registros, sin valores NULL ni filas
--   completamente duplicadas. PRODUCT_ID es único y no nulo.
-- - No se encontraron valores negativos ni ceros en PRODUCT_ID
--   ni en MANUFACTURER.
-- - Se detectaron 15 campos vacíos después de TRIM en cada columna:
--   DEPARTMENT, COMMODITY_DESC y SUB_COMMODITY_DESC, y 30.607
--   en CURR_SIZE_OF_PRODUCT.
-- - Se encontraron 490 etiquetas NO COMMODITY DESCRIPTION
--   y 429 etiquetas NO SUBCOMMODITY DESCRIPTION.
-- - Todos los productos distintos de TRANSACTION_DATA (92.339),
--   CAUSAL_DATA (68.377) y COUPON (44.133) existen en PRODUCT.
-- - No se detectaron variantes de categorías por mayúsculas,
--   minúsculas o espacios exteriores entre los textos no vacíos.
--
-- CONSIDERACIONES PROPUESTAS PARA EL ETL:
-- - Conservar los productos y sus relaciones, aunque presenten
--   atributos descriptivos faltantes.
-- - Tratar la información descriptiva faltante en dbt mediante
--   TRIM y la conversión de textos vacíos a NULL, sin asumir
--   la causa de su ausencia ni inventar valores.
-- - Documentar las etiquetas de descripción no proporcionada
--   y conservar los datos originales en la fuente.
-- - Incorporar pruebas de unicidad y ausencia de nulos en
--   PRODUCT_ID, y de correspondencia con las tablas relacionadas.
--
-- CONCLUSIÓN FINAL:
-- PRODUCT presenta identificadores únicos y correspondencia completa
-- con los productos de las tablas relacionadas. Sin embargo, contiene
-- información descriptiva faltante, principalmente en el tamaño
-- del producto, que deberá tratarse en dbt. Con estos hallazgos
-- documentados, se da por finalizada la revisión de calidad.
-- ============================================================