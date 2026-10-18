-- ============================================================
-- EVALUACIÓN DE CALIDAD DE DATOS: TRANSACTION_DATA
-- Proyecto: Data Warehouse
-- Alcance: valores nulos, duplicados exactos, valores negativos,
-- integridad referencial, valores inconsistentes y decisiones ETL.
-- Todas las consultas son de solo lectura.
-- ============================================================

-- Cantidad total de registros analizados.
SELECT COUNT(*) AS total_registros
FROM public.transaction_data;

-- 1. IDENTIFICACIÓN DE VALORES NULOS
-- Se revisan los datos faltantes de todas las columnas.
SELECT
    COUNT(*) AS total_registros,
    COUNT(*) FILTER (WHERE household_key IS NULL) AS hogares_nulos,
    COUNT(*) FILTER (WHERE "BASKET_ID" IS NULL) AS canastas_nulas,
    COUNT(*) FILTER (WHERE "DAY" IS NULL) AS dias_nulos,
    COUNT(*) FILTER (WHERE "PRODUCT_ID" IS NULL) AS productos_nulos,
    COUNT(*) FILTER (WHERE "QUANTITY" IS NULL) AS cantidades_nulas,
    COUNT(*) FILTER (WHERE "SALES_VALUE" IS NULL) AS ventas_nulas,
    COUNT(*) FILTER (WHERE "STORE_ID" IS NULL) AS tiendas_nulas,
    COUNT(*) FILTER (WHERE "RETAIL_DISC" IS NULL) AS descuentos_nulos,
    COUNT(*) FILTER (WHERE "TRANS_TIME" IS NULL) AS horas_nulas,
    COUNT(*) FILTER (WHERE "WEEK_NO" IS NULL) AS semanas_nulas,
    COUNT(*) FILTER (WHERE "COUPON_DISC" IS NULL) AS cupones_descuento_nulos,
    COUNT(*) FILTER (WHERE "COUPON_MATCH_DISC" IS NULL) AS descuentos_adicionales_nulos
FROM public.transaction_data;

-- 2. IDENTIFICACIÓN DE REGISTROS DUPLICADOS
-- Se cuentan únicamente las filas idénticas en todas las columnas.
-- La repetición de un hogar, producto o canasta no implica por sí sola duplicidad.
SELECT
    (SELECT COUNT(*) FROM public.transaction_data) AS total_registros,
    COUNT(*) AS registros_unicos,
    (SELECT COUNT(*) FROM public.transaction_data) - COUNT(*) AS registros_duplicados
FROM (SELECT DISTINCT * FROM public.transaction_data) AS datos_unicos;

-- 3. IDENTIFICACIÓN DE VALORES NEGATIVOS
-- Se revisan todas las columnas numéricas. Los descuentos negativos
-- pueden representar rebajas y no constituyen errores automáticamente.
SELECT
    COUNT(*) FILTER (WHERE household_key < 0) AS hogares_negativos,
    COUNT(*) FILTER (WHERE "BASKET_ID" < 0) AS canastas_negativas,
    COUNT(*) FILTER (WHERE "DAY" < 0) AS dias_negativos,
    COUNT(*) FILTER (WHERE "PRODUCT_ID" < 0) AS productos_negativos,
    COUNT(*) FILTER (WHERE "QUANTITY" < 0) AS cantidades_negativas,
    COUNT(*) FILTER (WHERE "SALES_VALUE" < 0) AS ventas_negativas,
    COUNT(*) FILTER (WHERE "STORE_ID" < 0) AS tiendas_negativas,
    COUNT(*) FILTER (WHERE "RETAIL_DISC" < 0) AS descuentos_minoristas_negativos,
    COUNT(*) FILTER (WHERE "TRANS_TIME" < 0) AS horas_negativas,
    COUNT(*) FILTER (WHERE "WEEK_NO" < 0) AS semanas_negativas,
    COUNT(*) FILTER (WHERE "COUPON_DISC" < 0) AS descuentos_cupon_negativos,
    COUNT(*) FILTER (WHERE "COUPON_MATCH_DISC" < 0) AS descuentos_adicionales_negativos
FROM public.transaction_data;

-- 4. INTEGRIDAD REFERENCIAL Y CORRESPONDENCIA ENTRE TABLAS

-- 4.1. Comprobar que los productos de las transacciones existan en PRODUCT.
SELECT
    COUNT(*) AS productos_distintos,
    COUNT(*) FILTER (WHERE p."PRODUCT_ID" IS NULL) AS productos_sin_correspondencia
FROM (SELECT DISTINCT "PRODUCT_ID" FROM public.transaction_data) AS t
LEFT JOIN (SELECT DISTINCT "PRODUCT_ID" FROM public.product) AS p
    ON t."PRODUCT_ID" = p."PRODUCT_ID";

-- 4.2. Comprobar la cobertura de información demográfica de los hogares.
-- Un hogar sin demografía no significa necesariamente una transacción errónea.
SELECT
    COUNT(*) AS hogares_distintos,
    COUNT(*) FILTER (WHERE h.household_key IS NOT NULL) AS hogares_con_demografia,
    COUNT(*) FILTER (WHERE h.household_key IS NULL) AS hogares_sin_demografia
FROM (SELECT DISTINCT household_key FROM public.transaction_data) AS t
LEFT JOIN (SELECT DISTINCT household_key FROM public.hh_demographic) AS h
    ON t.household_key = h.household_key;

-- 4.3. Comprobar correspondencia con CAUSAL_DATA por producto, tienda y semana.
-- La ausencia de coincidencia puede indicar cobertura promocional parcial;
-- no debe interpretarse automáticamente como error de integridad.
SELECT
    COUNT(*) AS combinaciones_distintas,
    COUNT(*) FILTER (WHERE c."PRODUCT_ID" IS NOT NULL) AS combinaciones_con_correspondencia,
    COUNT(*) FILTER (WHERE c."PRODUCT_ID" IS NULL) AS combinaciones_sin_correspondencia
FROM (
    SELECT DISTINCT "PRODUCT_ID", "STORE_ID", "WEEK_NO"
    FROM public.transaction_data
) AS t
LEFT JOIN (
    SELECT DISTINCT "PRODUCT_ID", "STORE_ID", "WEEK_NO"
    FROM public.causal_data
) AS c
    ON t."PRODUCT_ID" = c."PRODUCT_ID"
   AND t."STORE_ID" = c."STORE_ID"
   AND t."WEEK_NO" = c."WEEK_NO";

-- 5. IDENTIFICACIÓN DE VALORES INCONSISTENTES
-- Se comprueban combinaciones de cantidad y venta que pueden
-- requerir interpretación, así como horas inválidas en formato HHMM.
-- Un valor en cero no representa necesariamente un error.
SELECT
    COUNT(*) FILTER (
        WHERE "QUANTITY" = 0 AND "SALES_VALUE" = 0
    ) AS cantidad_y_venta_cero,
    COUNT(*) FILTER (
        WHERE "QUANTITY" = 0 AND "SALES_VALUE" > 0
    ) AS cantidad_cero_venta_positiva,
    COUNT(*) FILTER (
        WHERE "QUANTITY" = 0
          AND ROUND("SALES_VALUE"::numeric, 2) >= 0.01
    ) AS cantidad_cero_venta_significativa,
    COUNT(*) FILTER (
        WHERE "QUANTITY" > 0 AND "SALES_VALUE" = 0
    ) AS cantidad_positiva_venta_cero,
    COUNT(*) FILTER (
        WHERE "TRANS_TIME" < 0
           OR "TRANS_TIME" > 2359
           OR "TRANS_TIME" % 100 > 59
    ) AS horas_invalidas
FROM public.transaction_data;

-- 6. RESULTADOS, CONCLUSIÓN Y DECISIONES PARA EL ETL
-- La evaluación de calidad de TRANSACTION_DATA queda finalizada
-- para los cuatro aspectos definidos en este proyecto.
--
-- RESULTADOS:
-- - Se analizaron 2.595.732 registros.
-- - No se identificaron valores nulos ni filas completamente duplicadas.
-- - No se encontraron valores negativos en identificadores, cantidad,
--   ventas, día, semana u hora.
-- - Se encontraron descuentos negativos: RETAIL_DISC (1.303.026),
--   COUPON_DISC (36.422) y COUPON_MATCH_DISC (17.449).
--   Estos valores pueden representar descuentos válidos; no se
--   clasifican automáticamente como errores.
-- - Los 92.339 productos distintos de las transacciones tienen
--   correspondencia en PRODUCT (0 productos sin correspondencia).
-- - De 2.500 hogares distintos, 801 tienen información demográfica
--   y 1.699 no tienen correspondencia en HH_DEMOGRAPHIC.
-- - De 2.370.784 combinaciones distintas de producto, tienda y semana,
--   483.320 coinciden con CAUSAL_DATA y 1.887.464 no coinciden.
-- - Se identificaron 14.399 registros con cantidad y venta en cero,
--   67 con cantidad cero y venta positiva (38 de importe significativo),
--   y 4.451 con cantidad positiva y venta cero.
-- - No se encontraron horas inválidas en formato HHMM.
--
-- DECISIONES PARA EL ETL Y EL DATA WAREHOUSE:
-- - Conservar las transacciones originales; no eliminar registros
--   únicamente por descuentos negativos o por falta de datos relacionados.
-- - Mantener el significado y signo de los descuentos al transformarlos.
-- - Permitir hogares sin atributos demográficos mediante un tratamiento
--   de valores desconocidos o no disponibles en el modelo dimensional.
-- - Integrar la información promocional sin excluir transacciones
--   que no tengan correspondencia en CAUSAL_DATA.
-- - Documentar estas decisiones en los modelos y pruebas de dbt.
-- - Revisar las reglas de tratamiento de cantidades y ventas en cero
--   antes de calcular indicadores; no descartar filas automáticamente.
--
-- CONCLUSIÓN FINAL:
-- Se completó la evaluación de calidad de TRANSACTION_DATA conforme
-- a los cinco criterios establecidos. No se detectaron nulos ni
-- duplicados exactos, y la relación con PRODUCT es completa para los
-- identificadores examinados. Los descuentos negativos y la cobertura
-- parcial de las tablas relacionadas se documentan para su tratamiento
-- en el ETL, sin considerarlos errores de manera automática.
-- Las combinaciones de cantidad y venta en cero se documentan como
-- posibles inconsistencias para definir su tratamiento en dbt.
-- Con estos hallazgos documentados se cierra la revisión de calidad
-- de esta tabla dentro del alcance del proyecto.
