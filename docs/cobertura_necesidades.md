# Cobertura de las necesidades de análisis

Este documento describe las tablas dinámicas de Excel construidas para cada
*stakeholder* a partir de las necesidades del documento del proyecto (Tabla 1,
*Stakeholders, necesidades de análisis*) y los campos del modelo dimensional
que usan.

## Resultado

Las 15 tablas dinámicas se construyen con las tablas actuales:
`fact_sales`, `dim_product`, `dim_household`, `dim_time` y
`dim_promotional_context`.

## Tablas dinámicas por stakeholder

El libro `tablas_dinamicas/proyectoDunnhumby.xlsx` tiene 15 tablas dinámicas,
una hoja por *stakeholder*. Todas usan el Modelo de datos de Excel y varias
incluyen segmentadores para filtrar por tienda, período, categoría o grupo de hogares.

### Gerencia general

| Consulta | Campos de la tabla dinámica |
| --- | --- |
| Total de ventas por período | Filas: `dim_time.calendar_year` y `month_name`. Valores: suma de `sales_value`. |
| Comparación de ventas entre tiendas | Filas: `fact_sales.store_id`. Valores: suma de `sales_value` y la medida `% Ventas`. |
| Productos que generan mayores ingresos | Filas: `dim_product.product_id` y `subcategory`. Valores: medida `Top diez productos`. |
| Ventas con y sin actividad promocional | Filas: `dim_promotional_context.has_promotion`. Valores: suma de `sales_value` y porcentaje del total. |

### Departamento de ventas

| Consulta | Campos de la tabla dinámica |
| --- | --- |
| Ventas y demanda por producto, categoría y tienda | Filas: `dim_product.category` y `product_id`. Valores: suma de `sales_value` y recuento distinto de `basket_id` (veces comprado). Segmentador: `store_id`. |
| Rendimiento de ventas por tienda y categoría | Filas: `store_id`. Columnas: `dim_time.calendar_year`. Valores: suma de `sales_value`. Segmentadores: `category` y `month_name`. |

### Departamento de marketing

| Consulta | Campos de la tabla dinámica |
| --- | --- |
| Hogares con y sin campañas vigentes el día de la compra | Filas: `household_in_active_campaign`. Valores: suma de `sales_value`, recuento distinto de `basket_id` y recuento distinto de `dim_household_id`. |
| Productos más comprados según la campaña vigente del hogar | Filas: `product_id` y `subcategory`. Valores: medida `Top 10 Veces Comprado`. Segmentador: `household_in_active_campaign`. |

### Encargados de promociones y cupones

| Consulta | Campos de la tabla dinámica |
| --- | --- |
| Descuentos totales por producto, categoría, tienda y período | Filas: `dim_product.category` y `product_id`. Valores: medida `Descuento Total`. Segmentadores: `store_id`, `calendar_year` y `month_name`. |
| Gasto de hogares con y sin canjes el mismo día | Filas: `household_with_redemption_today`. Valores: suma de `sales_value` y medida `Gasto promedio por día de compra`. |
| Productos elegibles para cupones frente a no elegibles | Filas: `product_associated_with_coupon` (`Coupon received`, `Coupon available`, `No coupon`). Valores: suma de `sales_value` y porcentaje del total. |

### Departamento de análisis comercial

| Consulta | Campos de la tabla dinámica |
| --- | --- |
| Frecuencia de compra por hogar | Filas: `dim_household.household_id`. Valores: recuento distinto de `basket_id` y de `dim_time_id` (días con compra). |
| Gasto por grupo de edad | Filas: `dim_household.age_group`. Valores: suma de `sales_value` y medida `Gasto promedio por hogar`. Segmentadores: `household_composition` e `income_range`. |
| Categorías más compradas | Filas: `dim_product.category`. Valores: recuento distinto de `basket_id`. |
| Comportamiento de compra por composición del hogar | Filas: `dim_household.household_composition`. Valores: medidas `Compras promedio por hogar`, `Gasto promedio por compra` y `Gasto promedio por hogar`. Segmentadores: `age_group` e `income_range`. |

## Columnas de origen que no se usan

| Tabla de origen | Columna | Motivo |
| --- | --- | --- |
| `campaign_table` | `DESCRIPTION` | El tipo de campaña se toma de `campaign_desc`, que trae el mismo valor. |
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
6. **Ventas y gasto:** según la guía de dunnhumby, `sales_value` es lo que
   recibe el comercio, no lo que pagó el cliente. Las consultas de "ventas" e
   "ingresos" lo usan tal cual. En las de "gasto del hogar" es una
   aproximación: si hubo cupón del fabricante, el cliente pagó
   `sales_value + coupon_discount`, porque el descuento es negativo.
