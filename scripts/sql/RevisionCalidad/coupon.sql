-- ============================================================
-- EVALUACIÓN DE CALIDAD DE DATOS: COUPON
-- Proyecto: Data Warehouse Dunnhumby
-- Tabla: public.coupon
-- Las consultas son de solo lectura; no modifican los datos.
-- ============================================================


-- 0. OBSERVACIÓN DE LA INFORMACIÓN
SELECT * FROM public.coupon;


-- 0.1. CANTIDAD TOTAL DE REGISTROS
SELECT COUNT(*) AS total_registros
FROM public.coupon;


-- 1. IDENTIFICACIÓN DE VALORES NULOS
-- Las tres columnas son numéricas; no se revisan textos vacíos.
SELECT
    COUNT(*) AS total_registros,
    COUNT(*) FILTER (
        WHERE "COUPON_UPC" IS NULL
    ) AS cupones_nulos,
    COUNT(*) FILTER (
        WHERE "PRODUCT_ID" IS NULL
    ) AS productos_nulos,
    COUNT(*) FILTER (
        WHERE "CAMPAIGN" IS NULL
    ) AS campanas_nulas
FROM public.coupon;


-- 2. IDENTIFICACIÓN DE REGISTROS DUPLICADOS
-- Se cuentan filas idénticas en las tres columnas.
-- Repetir solo COUPON_UPC no significa que exista un duplicado.
SELECT
    (SELECT COUNT(*) FROM public.coupon) AS total_registros,
    COUNT(*) AS registros_unicos,
    (SELECT COUNT(*) FROM public.coupon)
        - COUNT(*) AS registros_duplicados
FROM (
    SELECT DISTINCT "COUPON_UPC", "PRODUCT_ID", "CAMPAIGN"
    FROM public.coupon
) AS datos_unicos;


-- 2.1. RESUMEN DE COMBINACIONES DUPLICADAS
-- Muestra cuántas combinaciones se repiten, cuántas filas
-- adicionales generan y la mayor cantidad de apariciones.
SELECT
    COUNT(*) AS combinaciones_repetidas,
    SUM(cantidad_registros - 1) AS filas_duplicadas_adicionales,
    MAX(cantidad_registros) AS maximas_repeticiones
FROM (
    SELECT COUNT(*) AS cantidad_registros
    FROM public.coupon
    GROUP BY "COUPON_UPC", "PRODUCT_ID", "CAMPAIGN"
    HAVING COUNT(*) > 1
) AS duplicados;


-- 3. IDENTIFICACIÓN DE VALORES NEGATIVOS Y CERO
-- Los resultados se documentan antes de clasificarlos como errores.
SELECT
    COUNT(*) FILTER (
        WHERE "COUPON_UPC" < 0
    ) AS cupones_negativos,
    COUNT(*) FILTER (
        WHERE "COUPON_UPC" = 0
    ) AS cupones_cero,
    COUNT(*) FILTER (
        WHERE "PRODUCT_ID" < 0
    ) AS productos_negativos,
    COUNT(*) FILTER (
        WHERE "PRODUCT_ID" = 0
    ) AS productos_cero,
    COUNT(*) FILTER (
        WHERE "CAMPAIGN" < 0
    ) AS campanas_negativas,
    COUNT(*) FILTER (
        WHERE "CAMPAIGN" = 0
    ) AS campanas_cero
FROM public.coupon;


-- 4. VERIFICACIÓN DE INTEGRIDAD REFERENCIAL


-- 4.1. CORRESPONDENCIA CON PRODUCT
-- Comprueba que los productos no nulos de COUPON existan en PRODUCT.
SELECT
    COUNT(*) AS productos_distintos,
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


-- 4.2. CORRESPONDENCIA CON CAMPAIGN_DESC
-- Comprueba que las campañas no nulas de COUPON
-- existan en el catálogo de campañas.
SELECT
    COUNT(*) AS campanas_distintas,
    COUNT(*) FILTER (
        WHERE cd."CAMPAIGN" IS NOT NULL
    ) AS campanas_con_correspondencia,
    COUNT(*) FILTER (
        WHERE cd."CAMPAIGN" IS NULL
    ) AS campanas_sin_correspondencia
FROM (
    SELECT DISTINCT "CAMPAIGN"
    FROM public.coupon
    WHERE "CAMPAIGN" IS NOT NULL
) AS c
LEFT JOIN (
    SELECT DISTINCT "CAMPAIGN"
    FROM public.campaign_desc
    WHERE "CAMPAIGN" IS NOT NULL
) AS cd
    ON c."CAMPAIGN" = cd."CAMPAIGN";


-- 4.3. CORRESPONDENCIA CON COUPON_REDEMPT
-- Comprueba que cada pareja no nula de cupón y campaña
-- utilizada en las redenciones exista en COUPON.
-- Se usan parejas distintas para evitar multiplicar los conteos
-- por los productos asociados a cada cupón.
SELECT
    COUNT(*) AS pares_cupon_campana_redimidos,
    COUNT(*) FILTER (
        WHERE c."COUPON_UPC" IS NOT NULL
    ) AS pares_con_correspondencia,
    COUNT(*) FILTER (
        WHERE c."COUPON_UPC" IS NULL
    ) AS pares_sin_correspondencia
FROM (
    SELECT DISTINCT "COUPON_UPC", "CAMPAIGN"
    FROM public.coupon_redempt
    WHERE "COUPON_UPC" IS NOT NULL
      AND "CAMPAIGN" IS NOT NULL
) AS r
LEFT JOIN (
    SELECT DISTINCT "COUPON_UPC", "CAMPAIGN"
    FROM public.coupon
    WHERE "COUPON_UPC" IS NOT NULL
      AND "CAMPAIGN" IS NOT NULL
) AS c
    ON r."COUPON_UPC" = c."COUPON_UPC"
   AND r."CAMPAIGN" = c."CAMPAIGN";


-- 5. CUPONES ASOCIADOS A VARIAS CAMPAÑAS
-- Cuenta los cupones asociados a más de una campaña
-- e identifica el máximo de campañas entre ellos.
-- Esta asociación no constituye un error automáticamente.
SELECT
    COUNT(*) AS cupones_con_varias_campanas,
    COALESCE(MAX(cantidad_campanas), 0) AS maximo_campanas_por_cupon
FROM (
    SELECT
        "COUPON_UPC",
        COUNT(DISTINCT "CAMPAIGN") AS cantidad_campanas
    FROM public.coupon
    WHERE "COUPON_UPC" IS NOT NULL
    GROUP BY "COUPON_UPC"
    HAVING COUNT(DISTINCT "CAMPAIGN") > 1
) AS cupones;


-- 5.1. RESUMEN DE PRODUCTOS POR CUPÓN Y CAMPAÑA
-- Se analizan todas las parejas de cupón y campaña.
-- COUNT DISTINCT evita contar varias veces el mismo producto
-- dentro de una pareja, aunque existan filas duplicadas.
-- Tener varios productos asociados no implica un error.
SELECT
    COUNT(*) AS total_pares_cupon_campana,
    COUNT(*) FILTER (
        WHERE productos_asociados = 1
    ) AS pares_con_un_producto,
    COUNT(*) FILTER (
        WHERE productos_asociados > 1
    ) AS pares_con_varios_productos,
    MIN(productos_asociados) AS minimo_productos,
    MAX(productos_asociados) AS maximo_productos
FROM (
    SELECT
        "COUPON_UPC",
        "CAMPAIGN",
        COUNT(DISTINCT "PRODUCT_ID") AS productos_asociados
    FROM public.coupon
    GROUP BY "COUPON_UPC", "CAMPAIGN"
) AS asociaciones;


-- ============================================================
-- RELACIONES TABLA: COUPON
-- ------------------------------------------------------------
-- -> PRODUCT
--    Columna de unión: PRODUCT_ID.
--    Propósito: identificar los atributos del producto asociado.
--
-- -> CAMPAIGN_DESC
--    Columna de unión: CAMPAIGN.
--    Propósito: identificar la campaña correspondiente.
--
-- -> COUPON_REDEMPT
--    Columnas de correspondencia: COUPON_UPC y CAMPAIGN.
--    Propósito: comprobar que los cupones redimidos tengan
--    una asociación registrada con su campaña en COUPON.
--
-- La unión directa con COUPON puede multiplicar las redenciones
-- por la cantidad de productos asociados. Debe respetarse
-- el nivel de detalle al integrar estas tablas.
-- ============================================================

-- ============================================================
-- 6. RESULTADOS Y CONSIDERACIONES PARA EL ETL: COUPON
-- ============================================================

-- RESULTADOS:
-- - Se analizaron 124.548 registros, sin valores NULL,
--   negativos ni ceros en las tres columnas.
-- - Se encontraron 119.384 combinaciones únicas de COUPON_UPC,
--   PRODUCT_ID y CAMPAIGN, y 5.164 filas duplicadas adicionales.
-- - Existen 1.824 combinaciones repetidas; la más frecuente
--   aparece 19 veces.
-- - Los 44.133 productos distintos existen en PRODUCT y
--   las 30 campañas distintas existen en CAMPAIGN_DESC.
-- - Las 643 parejas de cupón y campaña utilizadas en
--   COUPON_REDEMPT existen en COUPON, sin faltantes.
-- - Se identificaron 171 cupones asociados a varias campañas,
--   con un máximo de 6 campañas por cupón.
-- - De las 1.397 parejas de cupón y campaña, 58 tienen
--   un producto y 1.339 tienen varios, con un máximo
--   de 14.477 productos distintos por pareja.
--   Estas asociaciones múltiples no implican errores por sí solas.
--
-- CONSIDERACIONES PROPUESTAS PARA EL ETL:
-- - Conservar los datos originales en la fuente y generar
--   un modelo con una fila por combinación de COUPON_UPC,
--   PRODUCT_ID y CAMPAIGN, para evitar asociaciones duplicadas.
-- - Mantener las asociaciones de un cupón con varios productos
--   y campañas; no deduplicar únicamente por COUPON_UPC.
-- - Relacionar las redenciones por COUPON_UPC y CAMPAIGN,
--   evitando multiplicar sus conteos por los productos asociados.
-- - Incorporar pruebas de ausencia de nulos, unicidad de la
--   combinación de las tres columnas y correspondencia
--   con PRODUCT y CAMPAIGN_DESC.
--
-- CONCLUSIÓN FINAL:
-- COUPON presenta correspondencia completa en las relaciones
-- revisadas y no contiene valores NULL, negativos ni ceros.
-- El principal hallazgo son las 5.164 filas duplicadas adicionales,
-- cuyo tratamiento se propone realizar en dbt. Las asociaciones
-- múltiples entre cupones, productos y campañas deben conservarse
-- respetando su nivel de detalle. Con estos hallazgos documentados,
-- se da por finalizada la revisión de calidad.
-- ============================================================