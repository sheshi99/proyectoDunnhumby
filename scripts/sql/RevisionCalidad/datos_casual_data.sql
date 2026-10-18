-- ============================================================
-- EVALUACIÓN DE CALIDAD DE DATOS: CAUSAL_DATA
-- Proyecto: Data Warehouse Dunnhumby
-- Tabla: public.causal_data
-- Las consultas son de solo lectura; no modifican los datos.
-- ============================================================

-- 1. IDENTIFICACIÓN DE VALORES NULOS
-- Se comprueba si existen datos faltantes en cada columna.
SELECT
    COUNT(*) AS total_registros,
    COUNT(*) FILTER (WHERE "PRODUCT_ID" IS NULL) AS productos_nulos,
    COUNT(*) FILTER (WHERE "STORE_ID" IS NULL) AS tiendas_nulas,
    COUNT(*) FILTER (WHERE "WEEK_NO" IS NULL) AS semanas_nulas,
    COUNT(*) FILTER (WHERE display IS NULL) AS display_nulos,
    COUNT(*) FILTER (WHERE mailer IS NULL) AS mailer_nulos
FROM public.causal_data;

-- 2. IDENTIFICACIÓN DE REGISTROS DUPLICADOS
-- Se identifican filas completamente idénticas.
SELECT
    COUNT(*) AS total_registros,
    COUNT(*) - (
        SELECT COUNT(*)
        FROM (
            SELECT DISTINCT *
            FROM public.causal_data
        ) AS datos_unicos
    ) AS registros_duplicados
FROM public.causal_data;

-- 3. IDENTIFICACIÓN DE VALORES NEGATIVOS
-- Solo se evalúan las columnas numéricas; display y mailer son texto.
SELECT
    COUNT(*) FILTER (WHERE "PRODUCT_ID" < 0) AS productos_negativos,
    COUNT(*) FILTER (WHERE "STORE_ID" < 0) AS tiendas_negativas,
    COUNT(*) FILTER (WHERE "WEEK_NO" < 0) AS semanas_negativas
FROM public.causal_data;

-- 4. VERIFICACIÓN DE INTEGRIDAD REFERENCIAL
-- Se comprueba que los productos distintos de CAUSAL_DATA existan en PRODUCT.
SELECT
    COUNT(*) AS productos_distintos,
    COUNT(*) FILTER (
        WHERE p."PRODUCT_ID" IS NULL
    ) AS productos_sin_correspondencia
FROM (
    SELECT DISTINCT "PRODUCT_ID"
    FROM public.causal_data
) c
LEFT JOIN (
    SELECT DISTINCT "PRODUCT_ID"
    FROM public.product
) p
    ON c."PRODUCT_ID" = p."PRODUCT_ID";

-- 5. IDENTIFICACIÓN DE VALORES INCONSISTENTES
-- Se buscan identificadores o semanas en cero y textos vacíos.
SELECT
    COUNT(*) FILTER (WHERE "PRODUCT_ID" = 0) AS productos_cero,
    COUNT(*) FILTER (WHERE "STORE_ID" = 0) AS tiendas_cero,
    COUNT(*) FILTER (WHERE "WEEK_NO" = 0) AS semanas_cero,
    COUNT(*) FILTER (WHERE TRIM(display) = '') AS display_vacios,
    COUNT(*) FILTER (WHERE TRIM(mailer) = '') AS mailer_vacios
FROM public.causal_data;

-- 5.1. REVISIÓN DE CÓDIGOS EN DISPLAY Y MAILER
-- Se listan las categorías presentes y su frecuencia.
-- Los códigos no se consideran errores sin conocer su significado.
SELECT
    'display' AS columna,
    display AS valor,
    COUNT(*) AS total_registros
FROM public.causal_data
GROUP BY display

UNION ALL

SELECT
    'mailer' AS columna,
    mailer AS valor,
    COUNT(*) AS total_registros
FROM public.causal_data
GROUP BY mailer

ORDER BY columna, total_registros DESC;

-- ============================================================
-- 6. CONCLUSIÓN FINAL Y CONSIDERACIONES PARA EL ETL
-- ============================================================
-- Se completó la evaluación de calidad de la tabla CAUSAL_DATA,
-- que contiene 36.786.524 registros.
-- No se identificaron registros completamente duplicados,
-- valores negativos en las columnas numéricas, identificadores
-- con valor cero ni campos de texto vacíos.
-- Los 68.377 productos distintos registrados en CAUSAL_DATA
-- tienen correspondencia con la tabla PRODUCT.
-- Las columnas DISPLAY y MAILER contienen diferentes códigos
-- utilizados para representar información promocional.
-- No se identificaron valores vacíos; sin embargo, su significado
-- deberá respetarse durante las transformaciones del Data Warehouse.
-- Con los resultados obtenidos, se da por finalizada la
-- evaluación de calidad de CAUSAL_DATA según los criterios
-- establecidos para el proyecto.
-- Durante el proceso ETL con dbt se conservarán los códigos
-- originales y se mantendrán las relaciones correspondientes
-- para integrar la información promocional al Data Warehouse.