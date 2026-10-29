# Cómo se crean las dimensiones con dbt

Las dimensiones son tablas que describen los productos, hogares, campañas,
días y condiciones promocionales de las ventas. Esta guía explica de dónde
salen y cómo se crean en la base de datos Data_warehouse.

## 1. Ubicación de los datos

| Base de datos | Esquema | Contenido |
| --- | --- | --- |
| `dunnhumby_etl` | `public` | Las ocho tablas originales. |
| `dunnhumby_etl` | `staging` | Las copias de trabajo, las vistas limpias `stg_` y la vista intermediaria `int_sales_promotional_context`. |
| `Data_warehouse` | `public` | Las cuatro dimensiones y `fact_sales`. |


## 2. Dimensiones y fuentes de datos

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

## 3. Configuración de los modelos

El modelo [dim_product.sql](../models/dimensions/dim_product.sql) contiene
la configuración y la consulta que dbt utiliza para crear la tabla de productos.

| Parte del modelo | Para qué sirve |
| --- | --- |
| `materialized='table'` | dbt crea una tabla con el resultado del `SELECT`. |
| `schema='public' if target.name == 'warehouse'` | Al usar la conexión `warehouse`, la tabla se crea en `public`. |
| `grants={'select': ['rol_data_warehouse']}` | Concede al rol permiso para consultar la tabla. |
| `post_hook` | Ejecuta instrucciones después de crear la tabla, por ejemplo agregar la clave primaria. |
| `SELECT` | Elige las columnas, sus nombres y sus tipos. `::bigint`, por ejemplo, convierte un valor a entero grande. |
| `staging_view('stg_product')` | Lee la vista limpia de la primera base de datos. |

`warehouse` es el nombre de la conexión en `profiles.yml`; esa conexión apunta
a la base `Data_warehouse`. No es el nombre de un esquema.

### Acceso a las vistas de staging

La macro [staging_view.sql](../macros/staging_view.sql) permite que los modelos
ejecutados en `Data_warehouse` consulten las vistas de `dunnhumby_etl.staging`.
Utiliza `dblink`, una función de PostgreSQL para consultar otra base de datos.

Durante la ejecución, la macro obtiene los nombres y tipos de las columnas
y genera la consulta de lectura de la vista de origen. Internamente utiliza
`ref()` para registrar la dependencia entre los modelos en dbt.

Las dimensiones y la tabla de hechos se relacionan mediante `ref()`, que
referencia sus tablas dentro de `Data_warehouse`. Las vistas de preparación
permanecen en `dunnhumby_etl.staging`.

## 4. Ejecución del flujo

Antes de ejecutar, las ocho tablas de trabajo deben existir en staging, y deben
estar configuradas las conexiones y permisos. Los archivos correspondientes son:

| Archivo | Dónde se utiliza |
| --- | --- |
| `staging_roles_permisos.sql` | En `dunnhumby_etl`, para los permisos de staging. |
| `warehouse_roles_permisos.sql` | En `Data_warehouse`, para los permisos de consulta del warehouse. |
| `conexion_warehouse.sql` | Con `psql` conectado a `Data_warehouse`, para configurar `dblink`. Lee variables del entorno; no se pega completo en pgAdmin. |
| `profiles.yml` | En el proyecto, para las conexiones `dev` y `warehouse`. `profiles.example.yml` es la plantilla. |

Los tres archivos SQL están en `scripts/sql/Configuraciones/`. El usuario que
ejecuta dbt necesita además permisos para crear sus vistas y tablas.

Ejecutar los comandos en PowerShell desde la raíz del proyecto, donde están
`.env` y `dbt_project.yml`, con el Python que tiene instaladas las dependencias
de `requirements-dbt.txt`. Cada paso debe terminar correctamente antes de iniciar
el siguiente.

**Paso 1: crear las vistas limpias y la vista intermedia en la base de datos Dunnhumby_etl.**

```powershell
python -m dotenv -f .env run -- dbt run --profiles-dir . --target dev --select path:models/staging path:models/intermediate
```

**Paso 2: crear las dimensiones y hechos en la base de datos Data_warehouse, y ejecutar sus pruebas.**

```powershell
python -m dotenv -f .env run -- dbt build --profiles-dir . --target warehouse --select path:models/dimensions path:models/facts
```

El segundo comando incluye hechos porque, al reconstruir el contexto promocional,
sus IDs pueden cambiar y `fact_sales` debe usar los IDs de la nueva dimensión.
El comando puede tardar varios minutos.

Para interpretar los comandos: `--target` elige la conexión, `--select` elige
las carpetas de modelos y `--profiles-dir .` busca el perfil en la carpeta actual.
`python -m dotenv -f .env run --` carga las variables del archivo `.env`.

Con `warehouse`, utilizar la selección indicada. Un `dbt run` sin selección,
o agregar `+` delante de un modelo, puede incluir también las vistas que deben
construirse en la primera base.

## 5. Verificación del resultado

En pgAdmin, abrir Query Tool conectado a **`Data_warehouse`**:

```sql
select * from public.dim_product limit 10;
select * from public.dim_household limit 10;
select * from public.dim_time limit 10;
select * from public.dim_promotional_context limit 10;
```

La [guía de hechos](guia_hechos_dbt.md) describe la construcción y validación
de la tabla de ventas.
