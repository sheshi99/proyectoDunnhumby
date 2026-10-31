# Cómo se crean las dimensiones con dbt

Las dimensiones describen los productos, hogares, días y condiciones
promocionales de las ventas. Esta guía explica de dónde salen, cómo están
configurados sus modelos y cómo se cargan en `Data_warehouse` (paso 9 del
[README](../README.md)).

## 1. Dimensiones y fuentes de datos

El modelo contiene cuatro dimensiones. Las campañas permanecen como fuentes en
staging para calcular los indicadores de contexto promocional. Gerencia, ventas,
marketing, promociones y análisis comercial utilizan esas dimensiones y las
medidas de `fact_sales` para sus consultas.

| Modelo y tabla resultante | De dónde obtiene los datos | Qué representa una fila |
| --- | --- | --- |
| `dim_product` | Vista `stg_product`. | Un producto, con fabricante, departamento, marca, categoría y tamaño. |
| `dim_household` | Vistas de transacciones, campañas por hogar, canjes y demografía. | Un hogar y sus datos demográficos disponibles. |
| `dim_time` | Vista `stg_transaction_data`. | Un día de ventas y la semana que registra el dataset. |
| `dim_promotional_context` | Vista `int_sales_promotional_context`. | Una combinación de condiciones promocionales. |


### Preparación de hogares en `dim_household`

El bloque `with households as (...)` es una consulta con nombre que se usa
dentro del mismo modelo. No crea otra tabla permanente.

1. Busca los IDs de hogares en compras, campañas, canjes y demografía.
2. Los reúne con `UNION`, que deja cada ID una sola vez.
3. Agrega los datos demográficos con `LEFT JOIN`.

Por ejemplo: si el hogar 100 compró pero no tiene perfil demográfico, sigue
apareciendo en la dimensión. Sus datos demográficos quedan en `NULL`.

### Construcción de `dim_promotional_context`

Primero, la vista `int_sales_promotional_context` reúne para cada línea de venta
información de anuncios, campañas, cupones y canjes. Esa vista permanece en staging.
Resume las coincidencias antes de unirlas a ventas para evitar multiplicarlas.

Después, el modelo de la dimensión toma estas siete columnas:

| Columna | Qué indica |
| --- | --- |
| `has_promotion` | Evidencia de promoción: verdadero, falso o desconocido (`NULL`). |
| `display_type` | Códigos de exhibición observados, guardados como lista JSON en texto. |
| `mailer_type` | Códigos de anuncio observados, guardados como lista JSON en texto. |
| `household_in_active_campaign` | Si el hogar tenía alguna campaña asignada vigente ese día. |
| `active_campaigns_count` | Cuántas campañas asignadas tenía activas. |
| `product_associated_with_coupon` | Si el producto tenía un cupón asociado a una campaña vigente. |
| `household_with_redemption_today` | Si el hogar registró algún canje ese día. |

`DISTINCT` guarda cada combinación de los siete valores una sola vez. Dos ventas
con la misma combinación comparten un `promotional_context_id`; ambas ventas
se conservan por separado en `fact_sales`.

Tener un cupón disponible no demuestra que se usó en esa compra. Un canje del
hogar tampoco identifica por sí solo el producto comprado.

## 2. Configuración de los modelos

Todas las tablas del warehouse las crea y actualiza dbt con la materialización
propia `cambios` ([incremental_sync.sql](../macros/incremental_sync.sql)):

- **Primera ejecución:** si la tabla no existe, la crea con las columnas y tipos
  del `SELECT`, agrega sus restricciones y la carga completa.
- **Siguientes ejecuciones:** compara el `SELECT` con la tabla y aplica solo
  inserciones, actualizaciones y eliminaciones, sin reemplazar la tabla.

Los permisos de lectura vienen de los permisos predeterminados de
`warehouse_roles_permisos.sql`. Por ejemplo,
[dim_product.sql](../models/dimensions/dim_product.sql):

| Parte del modelo | Para qué sirve |
| --- | --- |
| `materialized='cambios'` | Crea la tabla si no existe y después la actualiza por diferencias. |
| `unique_key` | Columna con la que se reconoce cada fila al comparar: `product_id`, `household_id`, `time_id` o `context_key`. Es la clave primaria, salvo que haya `identity_column`. |
| `identity_column` | ID generado por la tabla y clave primaria: `promotional_context_id` y `sale_detail_id`. Se conserva en las actualizaciones. |
| `not_null_columns`, `unique_columns` | Restricciones adicionales al crear la tabla; por ejemplo, `dataset_day_number` en `dim_time`. |
| `foreign_keys` | En `fact_sales`, la dimensión a la que apunta cada columna. |
| `schema='public' if target.name == 'warehouse'` | Con la conexión `warehouse`, las tablas están en `public`. |
| `SELECT` | Elige las columnas, sus nombres y sus tipos. `::bigint`, por ejemplo, convierte a entero grande. |
| `staging_view('stg_product')` | Lee la vista limpia de la primera base. |

`warehouse` es el nombre de la conexión en `profiles.yml`, que apunta a la base
`Data_warehouse`; no es un esquema.

### Acceso a las vistas de staging

La macro [staging_view.sql](../macros/staging_view.sql) permite que los modelos
ejecutados en `Data_warehouse` consulten las vistas de `dunnhumby_etl.staging`
mediante `dblink`. Obtiene los nombres y tipos de las columnas, genera la
consulta de lectura y usa `ref()` para registrar la dependencia entre modelos.

## 3. Ejecución

Requiere los pasos 1 a 8 del [README](../README.md) completos: vistas de staging,
conexiones, `dblink` y permisos.

Crear y cargar las dimensiones y la tabla de hechos y ejecutar sus pruebas:

```powershell
python -m dotenv -f .env run -- dbt build `
    --profiles-dir . `
    --target warehouse `
    --select path:models/dimensions path:models/facts
```

`--target warehouse` elige la conexión a `Data_warehouse`, `--select` elige las
carpetas de modelos y `dbt build` crea o actualiza las tablas y ejecuta sus pruebas.
dbt crea primero las dimensiones y después `fact_sales`, porque sus claves
foráneas apuntan a ellas.

La primera ejecución crea las tablas, inserta todos los datos y puede tardar varios minutos. Las
siguientes solo aplican diferencias; normalmente las hace el
[job automático](job_etl.md). `--full-refresh` está deshabilitado para no perder
los IDs.

Con `warehouse`, usar siempre esta selección. Un `dbt run` sin selección, o un
`+` delante de un modelo, incluiría las vistas que deben crearse en la primera base.

## 4. Verificación del resultado

En pgAdmin, abrir Query Tool conectado a **`Data_warehouse`**:

```sql
select * from public.dim_product limit 10;
select * from public.dim_household limit 10;
select * from public.dim_time limit 10;
select * from public.dim_promotional_context limit 10;
```

La [guía de hechos](guia_hechos_dbt.md) describe la construcción y validación
de la tabla de ventas.
