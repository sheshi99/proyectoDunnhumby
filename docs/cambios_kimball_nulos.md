# Cambios para aplicar Kimball a los valores nulos

Este documento describe qué se va a cambiar en el modelo para seguir las
recomendaciones de Kimball sobre valores nulos, en qué archivos y qué se debe
ejecutar después.

## Reglas de Kimball que se aplican

1. Los atributos de las dimensiones no quedan en `NULL`: se reemplazan por un
   texto que describe por qué falta el dato.
2. Los indicadores verdadero/falso de las dimensiones se guardan como texto,
   para que se entiendan en los reportes.
3. Las claves foráneas de la tabla de hechos nunca son `NULL`.
4. Las medidas de la tabla de hechos no se modifican.

Los textos van en inglés, igual que las columnas y los valores de la fuente.
No se usa `Unknown` porque la fuente ya lo trae con otro significado.

## Textos definidos

### `dim_household`

| Caso | Texto |
| --- | --- |
| Hogar sin perfil demográfico | `'No demographic profile'` |

### `dim_product`

| Caso | Texto |
| --- | --- |
| Departamento, marca, categoría, subcategoría o tamaño vacío | `'not available'` |

Va en minúscula porque `stg_product` convierte todos los textos a minúscula.

### `dim_promotional_context`

| Columna | Antes | Después |
| --- | --- | --- |
| `has_promotion` | `TRUE` / `FALSE` / `NULL` | `'Promotion'` / `'No promotion'` / `'Undetermined'` |
| `display_type` | lista JSON o `NULL` | lista JSON o `'No causal data'` |
| `mailer_type` | lista JSON o `NULL` | lista JSON o `'No causal data'` |
| `household_in_active_campaign` | `TRUE` / `FALSE` | `'In campaign'` / `'Not in campaign'` |
| `product_associated_with_coupon` | `TRUE` / `FALSE` | `'Coupon available'` / `'No coupon'` |
| `household_with_redemption_today` | `TRUE` / `FALSE` | `'Redeemed'` / `'Not redeemed'` |
| `active_campaigns_count` | número | sin cambio |

`'No promotion'` y `'Undetermined'` mantienen la diferencia entre "se sabe que
no hubo promoción" y "no se puede saber".

## Cambios por archivo

### 1. Nuevo: `models/intermediate/int_household.sql`

Vista en staging que reúne los hogares de ventas, campañas, canjes y demografía
(`union`) y les agrega su perfil (`left join` con `stg_hh_demographic`). Los
siete atributos demográficos usan `coalesce(..., 'No demographic profile')`.

Esta lógica hoy está en `dim_household.sql`; se mueve a staging para que las
dimensiones solo hagan un `select`.

### 2. `models/dimensions/dim_household.sql`

| Antes | Después |
| --- | --- |
| `union` de cuatro vistas y `left join` con demografía | `select * from {{ staging_view('int_household') }}` |

### 3. `models/staging/stg_product.sql`

| Antes | Después |
| --- | --- |
| `nullif(lower(btrim("DEPARTMENT")), '')` | `coalesce(nullif(lower(btrim("DEPARTMENT")), ''), 'not available')` |

Igual en `brand`, `category`, `subcategory` y `product_size`.

### 4. `models/intermediate/int_sales_promotional_context.sql`

En el `select` final, cada columna de la tabla de contexto se convierte a texto:

```sql
case causal.has_promotion
    when true then 'Promotion'
    when false then 'No promotion'
    else 'Undetermined'
end as has_promotion,
coalesce(causal.display_type, 'No causal data') as display_type,
coalesce(causal.mailer_type, 'No causal data') as mailer_type,
case when coalesce(campaigns.active_campaigns_count, 0) > 0
    then 'In campaign' else 'Not in campaign' end as household_in_active_campaign,
case when coupons.product_id is not null
    then 'Coupon available' else 'No coupon' end as product_associated_with_coupon,
case when redemptions.household_id is not null
    then 'Redeemed' else 'Not redeemed' end as household_with_redemption_today,
```

### 5. Sin cambios

| Archivo | Motivo |
| --- | --- |
| `dim_product.sql` | Recibe los textos ya preparados en `stg_product`. |
| `dim_time.sql` | No tiene nulos. |
| `dim_promotional_context.sql` | Toma las columnas de la vista intermedia; solo cambia su tipo. |
| `fact_sales.sql` | El join con el contexto compara las mismas columnas. Sus claves y medidas no cambian. |

### 6. Documentación

| Archivo | Qué cambia |
| --- | --- |
| `models/staging/staging.yml` | Descripción de `stg_product`: ya no convierte vacíos en `NULL`. |
| `models/dimensions/dimensions.yml` | Descripciones de `dim_household` y `dim_promotional_context` que mencionan `NULL`. |
| `docs/tratamiento_nulos.md` | Reemplazar la regla "evitar datos ficticios" por la de Kimball y actualizar las tablas de resumen. |
| `docs/guia_dimensiones_dbt.md` | Explicación de `dim_household`, que pasa a leer de `int_household`. |

## Tablas que se deben recrear

| Tabla | ¿Recrear? | Motivo |
| --- | --- | --- |
| `dim_household` | No | Las columnas siguen siendo texto; el job actualiza las filas. |
| `dim_product` | No | Igual que la anterior. |
| `dim_time` | No | Sin cambios. |
| `dim_promotional_context` | **Sí** | Cuatro columnas pasan de booleano a texto, y la materialización no modifica columnas de tablas existentes. |
| `fact_sales` | **Sí** | Tiene una clave foránea hacia `dim_promotional_context`. |

Al recrearlas, `promotional_context_id` y `sale_detail_id` se generan de nuevo.
Los IDs de productos, hogares y tiempo no cambian.

## Orden de ejecución

Con el job de pgAgent detenido o sin ejecuciones en curso:

1. Actualizar las vistas de staging, desde la carpeta del proyecto:

   ```powershell
   dbt run --target dev --select stg_product int_household int_sales_promotional_context
   ```

2. Borrar las tablas que cambian de tipo, en Query Tool conectado a
   `Data_warehouse`:

   ```sql
   DROP TABLE public.fact_sales;
   DROP TABLE public.dim_promotional_context;
   ```

3. Ejecutar el job, que recrea esas dos tablas y actualiza las demás:

   ```powershell
   .\logs\jobs\pgagent_ejecutar.cmd
   ```

4. Comprobar que `logs/jobs/ultima_ejecucion.json` diga `"estado": "CORRECTO"`
   y que no queden nulos:

   ```sql
   SELECT count(*) FROM dim_household WHERE age_group IS NULL;
   SELECT count(*) FROM dim_product WHERE department IS NULL;
   SELECT count(*) FROM dim_promotional_context WHERE display_type IS NULL;
   ```

   Los tres conteos deben ser `0`.

## Pendiente

`display_type` y `mailer_type` siguen guardando los códigos como lista JSON
(por ejemplo, `["0","3"]`). Kimball recomendaría traducirlos a una descripción
legible. Queda por decidir si se hace.
