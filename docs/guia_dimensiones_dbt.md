# Guía del equipo: dimensiones en dbt

Esta guía explica las cinco dimensiones que construimos, las decisiones tomadas y cómo ejecutarlas. Una dimensión guarda información descriptiva que permitirá analizar las ventas por producto, hogar, campaña, tiempo o contexto promocional.

El recorrido de los datos es:

**Tablas originales en `staging` → vistas limpias `stg_` → dimensiones en `data_warehouse`.** Para contexto promocional hay un paso adicional entre las vistas limpias y la dimensión: `int_sales_promotional_context`.

Partimos de las ocho vistas de staging y reutilizamos su limpieza. Los modelos están en `models/dimensions/` y se materializan como tablas: dbt ejecuta cada consulta SQL y guarda su resultado. No necesitamos escribir un `INSERT` aparte.

## 1. Qué contiene cada dimensión

| Dimensión | Qué representa una fila | Origen y preparación | Clave primaria |
| --- | --- | --- | --- |
| `dim_product` | Un producto. | Toma `stg_product` y conserva fabricante, departamento, marca, categoría, subcategoría y tamaño. Ajusta nombres y tipos de columnas. | `product_id`, conservado de la fuente. |
| `dim_campaign` | Una campaña. | Toma `stg_campaign_descriptions` y guarda el tipo de campaña como descripción, junto con los días de inicio y fin. | `campaign_id`, conservado de la fuente. |
| `dim_household` | Un hogar conocido. | Reúne hogares de compras, asignaciones a campañas, canjes y demografía; después incorpora sus atributos demográficos. | `household_id`, conservado de la fuente. |
| `dim_time` | Un día observado en las compras. | Obtiene el día y la semana de `stg_transaction_data`, sin asignar fechas de calendario. | `time_id`, igual al número de día del dataset. |
| `dim_promotional_context` | Una combinación de atributos promocionales observada en compras. | Guarda las condiciones promocionales descritas en la sección 2, sin productos ni importes de ventas. | `promotional_context_id`, primera columna y clave propia `IDENTITY`. |

En **hogares**, usamos `UNION` para reunir identificadores sin repetirlos y `LEFT JOIN` para agregar la demografía. Así conservamos los hogares sin perfil, con atributos `NULL`.

En **tiempo**, conservamos la semana registrada en la fuente; no la calculamos dividiendo el día entre siete. Como no conocemos la fecha base, no inventamos meses ni años. Las restricciones impiden días duplicados y valores nulos de día o semana; si un día aparece con dos semanas distintas, la carga falla.

Los días de inicio y fin de **campañas** también son índices del dataset. La asignación de campañas a hogares se obtiene de `stg_campaign_table`, no de `dim_campaign`.

## 2. Cómo leer los modelos de contexto promocional

Para seguir el código, abrir estos dos archivos en este orden:

1. `models/intermediate/int_sales_promotional_context.sql`: consulta las vistas limpias y calcula la información promocional que acompaña a cada compra.
2. `models/dimensions/dim_promotional_context.sql`: guarda las descripciones promocionales en una tabla y les asigna una clave propia.

### Paso 1. Identificar qué información necesitamos

Las vistas `stg_` ya están limpias, pero cada una contiene información diferente. La compra indica el hogar, el producto, la tienda y el día; otras vistas indican anuncios, campañas y cupones. Para saber qué condiciones promocionales acompañaban a esa compra, el primer archivo consulta esas fuentes:

| Qué consulta | Qué obtiene |
| --- | --- |
| Anuncios del producto en la tienda y semana de la compra. | Si había exhibición o anuncio y sus códigos. |
| Campañas asignadas al hogar y sus días de vigencia. | Cuántas campañas tenía activas ese día. |
| Cupones asociados al producto y campañas vigentes. | Si existía un cupón asociado al producto ese día. |
| Canjes del hogar en el día de la compra. | Si el hogar registró algún canje ese día. |

Esto calcula información que no aparece junta en una sola vista de origen. Por ejemplo, para contar campañas activas necesitamos consultar tanto la asignación al hogar como las fechas de la campaña.

### Paso 2. Mantener una fila por compra

En el primer archivo, los bloques `WITH` preparan los resultados antes de unirlos a las compras. Por ejemplo, si un hogar tiene dos campañas activas, se obtiene el número `2` para ese hogar y día. Así podemos agregar ese número a su compra sin convertirla en dos compras.

Los `LEFT JOIN` agregan los resultados y conservan las compras que no tienen coincidencias. El resultado actual de este archivo es una vista con las columnas originales de las ventas más los indicadores promocionales. Es una vista de preparación; no es la dimensión ni una tabla adicional del esquema estrella final.

### Paso 3. Crear una descripción por contexto

En el segundo archivo, el `SELECT` toma únicamente los siete atributos promocionales. No selecciona producto, hogar, cesta, código de cupón, cantidades ni importes.

**Aquí `DISTINCT` no significa que las compras estén sucias o duplicadas.** Dos compras diferentes pueden tener exactamente las mismas condiciones promocionales. La dimensión necesita guardar esa descripción una sola vez.

Ejemplo ilustrativo, mostrando solo dos de los siete atributos:

| Compra original | Producto | Tiene promoción | Campañas activas |
| --- | --- | --- | --- |
| A | Arroz | Sí | 2 |
| B | Leche | Sí | 2 |

Las compras A y B son diferentes y ambas se conservan. Al seleccionar solamente «tiene promoción» y «campañas activas», obtenemos dos veces la descripción «Sí, 2». `DISTINCT` permite guardarla una sola vez en la dimensión. En el código real se comparan **los siete atributos juntos**: basta con que uno cambie para que sea otro contexto.

PostgreSQL asigna a cada descripción su `promotional_context_id` mediante `IDENTITY`. Esa clave permite relacionar muchas compras con una misma descripción promocional, manteniendo cada transacción y su importe en la tabla de hechos.

### Paso 4. Interpretar las columnas de la dimensión

| Columna | Significado |
| --- | --- |
| `promotional_context_id` | Identificador propio de la descripción promocional. |
| `has_promotion` | `true`: hay evidencia de exhibición o anuncio; `false`: ausencia explícita; `NULL`: información insuficiente. |
| `display_type` / `mailer_type` | Listas de códigos de exhibición y anuncio, guardadas como texto JSON. |
| `household_in_active_campaign` | El hogar tiene al menos una campaña asignada vigente ese día. |
| `active_campaigns_count` | Cantidad de campañas asignadas vigentes para el hogar. |
| `product_associated_with_coupon` | El producto está asociado a un cupón de una campaña vigente; no demuestra que se usó en la compra. |
| `household_with_redemption_today` | El hogar registró algún canje ese día; no identifica el producto que recibió el descuento. |

## 3. Cómo funciona la configuración

Al inicio de cada modelo, `config()` define la materialización como `table`, el esquema `data_warehouse` y los permisos de lectura para `rol_data_warehouse`. Los `post_hook` agregan las claves primarias y otras restricciones después de cargar el resultado; en contexto promocional también agregan el identificador `IDENTITY`.

Dentro de las consultas, **`ref('nombre_del_modelo')`** referencia otro modelo y permite que dbt determine el orden de ejecución. Por ejemplo, `dim_product` depende de `stg_product`.

Dos archivos completan la configuración:

- `macros/generate_schema_name.sql`: hace que las dimensiones se creen exactamente en `data_warehouse`, sin el prefijo `staging_`. dbt aplica esta macro automáticamente.
- `models/dimensions/dimensions.yml`: documenta las dimensiones y sus columnas; por sí solo no crea tablas.

## 4. Cómo ejecutarlas y revisar el resultado

Desde la raíz del proyecto, con el entorno Python activo, las tablas fuente disponibles y `.env` y `profiles.yml` configurados con `DBT_PG_SCHEMA=staging`, ejecutar:

```powershell
python -m dotenv -f .env run -- dbt run --profiles-dir .
```

Este es el **comando general**: ejecuta todos los modelos del proyecto, sin escribir sus nombres. Actualmente crea o reconstruye las ocho vistas `stg_`, la vista `int_sales_promotional_context`, las cinco tablas de dimensiones y `fact_sales`. Si después agregamos otros modelos, también los incluirá.

dbt lee los `ref()` y determina el orden: primero las vistas limpias, luego la vista intermedia y después la dimensión que la utiliza. No hay que ejecutar el intermediario manualmente. Las tablas originales deben existir previamente; este comando no las importa. La carga del contexto promocional puede tardar varios minutos.

Para trabajar solamente una dimensión y sus entradas, podemos usar un selector:

```powershell
python -m dotenv -f .env run -- dbt run --select +dim_promotional_context --profiles-dir .
```

El `+` anterior al nombre incluye todas sus dependencias: en este ejemplo, también ejecuta `int_sales_promotional_context` y las vistas `stg_` que necesita, aunque no aparezcan escritas en el comando. Sin el `+`, solo se ejecuta el modelo seleccionado y se asume que sus entradas ya existen. Si usamos el comando general, no hace falta repetir esta ejecución individual.

El usuario de conexión necesita lectura de las fuentes y permisos para crear objetos en los esquemas de destino. Los modelos con `{{ ... }}` se ejecutan mediante dbt, no pegándolos directamente en pgAdmin.


```sql
select * from data_warehouse.dim_product limit 10;
```