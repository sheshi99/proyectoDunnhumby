# Cobertura de las necesidades de análisis

Este documento comprueba que el modelo dimensional permite crear en Excel las
tablas dinámicas propuestas para cada *stakeholder* en el documento del proyecto
(Tabla 1, *Stakeholders, necesidades de análisis*).

## Resultado

Todas las consultas propuestas se pueden construir con las tablas actuales:
`fact_sales`, `dim_product`, `dim_household`, `dim_time` y
`dim_promotional_context`.

## Consultas por stakeholder

### Gerencia general

| Consulta | Campos de la tabla dinámica |
| --- | --- |
| Total de ventas por período | Filas: `dim_time.calendar_year`, `quarter_name`, `month_name` o `calendar_date`. Valores: suma de `sales_value`. |
| Comparación de ventas entre tiendas | Filas: `fact_sales.store_id`. Valores: suma de `sales_value`. |
| Productos que generan mayores ingresos | Filas: `dim_product.product_id`, `brand` o `category`. Valores: suma de `sales_value`, ordenada de mayor a menor. |
| Ventas con y sin actividad promocional | Filas: `dim_promotional_context.has_promotion`. Valores: suma de `sales_value`. |

### Departamento de ventas

| Consulta | Campos de la tabla dinámica |
| --- | --- |
| Ventas por producto, categoría y tienda | Filas: `dim_product.category` y `store_id`. Valores: suma de `sales_value`. |
| Productos más vendidos | Filas: `dim_product`. Valores: suma de `quantity`, ordenada de mayor a menor. |
| Cantidades vendidas por período | Filas: `dim_time.month_name` o `week_name`. Valores: suma de `quantity`. |
| Comparación de ventas entre tiendas | Filas: `store_id`. Valores: suma de `sales_value` y `quantity`. |

### Departamento de marketing

| Consulta | Campos de la tabla dinámica |
| --- | --- |
| Hogares con y sin campañas vigentes el día de la compra | Filas: `household_in_active_campaign`. Valores: suma de `sales_value` y `quantity`. |
| Gasto según la cantidad de campañas vigentes | Filas: `active_campaigns_count`. Valores: suma y promedio de `sales_value`. |
| Gasto del hogar en días con y sin campañas | Filas: `household_id`. Columnas: `household_in_active_campaign`. Valores: suma de `sales_value`. |

### Encargados de promociones y cupones

| Consulta | Campos de la tabla dinámica |
| --- | --- |
| Descuentos totales y promedio por línea | Filas: `category`, `store_id` o `dataset_week_number`. Valores: suma y promedio de `retail_discount`, `coupon_discount` y `manufacturer_coupon_discount`. |
| Ventas con y sin promoción, distinguiendo los casos sin cobertura | Filas: `has_promotion` (tres estados: con promoción, sin promoción y no determinado). Valores: suma de `sales_value` y `quantity`. |
| Gasto de hogares con y sin canjes el mismo día | Filas: `household_with_redemption_today`. Valores: suma de `sales_value`. |
| Productos elegibles para cupones frente a no elegibles | Filas: `product_associated_with_coupon`. Valores: suma de `sales_value` y `quantity`. |

### Departamento de análisis comercial

| Consulta | Campos de la tabla dinámica |
| --- | --- |
| Frecuencia de compra por hogar | Filas: `household_id`. Valores: recuento distinto de `basket_id`. |
| Gasto por grupo demográfico | Filas: `dim_household.age_group`, `income_range` u otro atributo. Valores: suma de `sales_value`. |
| Categorías más compradas | Filas: `dim_product.category`. Valores: suma de `quantity`. |
| Comparación entre grupos de hogares | Filas: un atributo de `dim_household`. Columnas: `category`. Valores: suma de `sales_value`. |

## Columnas de origen que no se usan

| Tabla de origen | Columna | Motivo |
| --- | --- | --- |
| `campaign_desc` | `DESCRIPTION` | Ninguna consulta compara tipos de campaña. |
| `campaign_table` | `DESCRIPTION` | Igual que la anterior. |
| `coupon` | `COUPON_UPC` | Solo se necesita saber si el producto tiene un cupón vigente. |
| `coupon_redempt` | `COUPON_UPC` | Solo se necesita saber si el hogar canjeó ese día. |
| `coupon_redempt` | `CAMPAIGN` | Igual que la anterior. |

Las necesidades de promociones y cupones indican que el análisis se hace *sin
atribuir un cupón específico a cada línea de venta*, por lo que el detalle del
cupón y de la campaña no es necesario.

## Consideraciones para Excel

1. **Período:** Dunnhumby no trae fechas reales. `dim_time` usa una fecha
   calculada desde la fecha base supuesta `2004-01-01`, con año, trimestre,
   mes, semana y día. Para ordenar los meses por calendario y no
   alfabéticamente, ordenar `month_name` por `calendar_month`.
2. **Relaciones:** en el Modelo de datos de Excel hay que relacionar
   `fact_sales` con cada dimensión por su ID propio (`dim_product_id`,
   `dim_household_id`, `dim_time_id` y `dim_promotional_context_id`). Sin esas relaciones no se pueden
   combinar campos de distintas tablas.
3. **Recuento distinto:** la frecuencia de compra lo necesita, y solo está
   disponible cuando los datos se cargan al Modelo de datos, como indica la
   [guía de conexión ODBC](conexion_excel_odbc.md).
4. **Tiendas:** `store_id` está en `fact_sales` y no tiene dimensión propia,
   porque la fuente no trae atributos de tiendas.
5. **Valores vacíos:** las dimensiones no tienen `NULL`. Los hogares sin
   demografía aparecen como `No demographic profile`, las promociones no
   determinadas como `Undetermined` y los indicadores como textos
   (`In campaign`, `Coupon available`, etc.). Ver
   [tratamiento de nulos](tratamiento_nulos.md).
