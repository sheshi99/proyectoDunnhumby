# Cómo se crea el modelo estrella con dbt

El modelo estrella tiene cuatro dimensiones y una tabla de hechos. Las
dimensiones describen los productos, hogares, días y condiciones promocionales
de las ventas. `fact_sales` guarda las ventas y las relaciona con las cuatro
dimensiones.

Esta guía explica de dónde salen, cómo están configurados sus modelos, cómo se
cargan en `Data_warehouse` (paso 9 del [README](../README.md)) y cómo se valida
el resultado (paso 10 del [README](../README.md)).

El modelo que carga los hechos es [fact_sales.sql](../models/facts/fact_sales.sql)
y la tabla está en **`Data_warehouse.public.fact_sales`**. Se carga junto con las
dimensiones, con el comando de la [sección 7](#7-ejecución).

Las medidas y dimensiones permiten elaborar consultas de gerencia, ventas,
marketing, promociones y análisis comercial.

## 1. Dimensiones y fuentes de datos

El modelo contiene cuatro dimensiones. Las campañas permanecen como fuentes en
staging para calcular los indicadores de contexto promocional. Gerencia, ventas,
marketing, promociones y análisis comercial utilizan esas dimensiones y las
medidas de `fact_sales` para sus consultas.

| Modelo y tabla resultante | De dónde obtiene los datos | Qué representa una fila |
| --- | --- | --- |
| `dim_product` | Vista `stg_product`. | Un producto, con fabricante, departamento, marca, categoría y tamaño. |
| `dim_household` | Vista `int_household`. | Un hogar y sus datos demográficos. |
| `dim_time` | Vista `int_time`. | Un día de ventas, con su fecha, sus atributos de calendario y la semana que registra el dataset. |
| `dim_promotional_context` | Vista `int_sales_promotional_context`. | Una combinación de condiciones promocionales. |

Las dimensiones solo insertan lo que traen sus vistas: las uniones y los
cálculos se hacen en staging.

### IDs de las dimensiones

Cada dimensión tiene un ID propio, que es su clave primaria y el que usa
`fact_sales`. El código original de Dunnhumby se conserva como una columna más,
con el mismo nombre que tiene en staging.

| Dimensión | ID propio | Código original |
| --- | --- | --- |
| `dim_product` | `dim_product_id` (1, 2, 3…) | `product_id` |
| `dim_household` | `dim_household_id` (1, 2, 3…) | `household_id` |
| `dim_time` | `dim_time_id` (fecha como 20040101) | `dataset_day_number` |
| `dim_promotional_context` | `dim_promotional_context_id` (1, 2, 3…) | — |

Así, `_id` sin prefijo siempre es el código de Dunnhumby, y `dim_..._id` siempre
es el ID del warehouse.

### Preparación de hogares en `int_household`

La vista [int_household.sql](../models/intermediate/int_household.sql) prepara
los hogares en staging:

1. Busca los IDs de hogares en compras, campañas, canjes y demografía.
2. Los reúne con `UNION`, que deja cada ID una sola vez.
3. Agrega los datos demográficos con `LEFT JOIN`.

Por ejemplo: si el hogar 100 compró pero no tiene perfil demográfico, sigue
apareciendo en la dimensión. Sus datos demográficos dicen
`'No demographic profile'`.

El estado civil se traduce según la guía de dunnhumby: `A` → `'Married'`,
`B` → `'Single'` y `U` → `'Unknown'`.

### Preparación del calendario en `int_time`

La vista [int_time.sql](../models/intermediate/int_time.sql) sigue la
dimensión de tiempo del curso. Para cada día de ventas calcula la fecha y sus
partes: año, trimestre, mes, semana del año, día del mes, día de la semana y
sus nombres (`Q1/04`, `January`, `Week 1/04`, `Thursday`).

La fecha sale de `transaction_date`, calculada en `stg_transaction_data` desde
la fecha base `2004-01-01`. La vista conserva también `DAY` y `WEEK_NO`
originales, porque los datos causales se unen por esa semana.

### Construcción de `dim_promotional_context`

Primero, la vista `int_sales_promotional_context` reúne para cada línea de venta
información de anuncios, campañas, cupones y canjes. Esa vista permanece en staging.
Resume las coincidencias antes de unirlas a ventas para evitar multiplicarlas.

Después, el modelo de la dimensión toma estas siete columnas:

| Columna | Qué indica |
| --- | --- |
| `has_promotion` | Evidencia de promoción: `'Promotion'`, `'No promotion'` o `'Undetermined'`. |
| `display_type` | Exhibición en tienda, descrita según la guía de dunnhumby (por ejemplo, `'In-aisle'`); si hay dos, se unen con `' + '`. `'No causal data'` sin cobertura. |
| `mailer_type` | Aparición en el folleto, descrita según la guía de dunnhumby (por ejemplo, `'Front page feature'`); si hay dos, se unen con `' + '`. `'No causal data'` sin cobertura. |
| `household_in_active_campaign` | Si el hogar tenía alguna campaña asignada vigente ese día. |
| `active_campaigns_count` | Cuántas campañas asignadas tenía activas. |
| `product_associated_with_coupon` | `'Coupon received'` si el hogar estaba en una campaña TypeB o TypeC vigente con cupón para el producto; `'Coupon available'` si había un cupón vigente sin saber si el hogar lo recibió; si no, `'No coupon'`. |
| `household_with_redemption_today` | Si el hogar registró algún canje ese día. |

`DISTINCT` guarda cada combinación de los siete valores una sola vez. Dos ventas
con la misma combinación comparten un `dim_promotional_context_id`; ambas ventas
se conservan por separado en `fact_sales`.

Tener un cupón disponible no demuestra que se usó en esa compra. Un canje del
hogar tampoco identifica por sí solo el producto comprado.

## 2. Tabla de hechos: qué información representa cada fila

La tabla de hechos registra lo ocurrido en las compras: qué producto se compró,
qué hogar realizó la compra, en qué día, cuántas unidades se registraron y cuáles
fueron los importes y descuentos. Las dimensiones guardan las descripciones que
permiten analizar esos datos, como la categoría del producto o el perfil del hogar.

En este proyecto, **cada fila de `fact_sales` corresponde a una fila original de
`transaction_data`**, preparada por las vistas de staging. A esta unidad de
información se le llama nivel de detalle o grano de la tabla.

Una cesta es el conjunto de productos registrados en una misma compra y se
identifica con `basket_id`. Una línea es uno de los registros que componen esa
cesta. Por eso, varias filas pueden tener el mismo `basket_id`: pertenecen a la
misma compra, pero conservan por separado los productos y sus medidas.

Ejemplo ilustrativo:

| Cesta | Producto | Cantidad | Importe |
| --- | --- | --- | --- |
| 500 | Arroz | 2 | 3.50 |
| 500 | Leche | 1 | 1.20 |

En esta compra hay dos líneas y se guardan dos filas de hechos. La línea del
arroz tiene cantidad 2, pero sigue siendo una fila: el modelo no crea una fila
por cada unidad. Tampoco reúne los dos productos en una sola fila por cesta.

`sale_detail_id` identifica cada fila de hechos; `basket_id` permite reconocer
cuáles pertenecen a la misma cesta. No se supone que la combinación de cesta
y producto sea única: se conservan todas las líneas que entrega la fuente,
incluso si varios de sus valores coinciden.

Con este detalle se pueden calcular después totales por producto, hogar o día.
La tabla conserva las líneas individuales; las sumas se realizan al consultarla.

## 3. Fuentes y construcción de la tabla de hechos

La construcción utiliza los siguientes objetos, cada uno con una responsabilidad:

| Objeto | Ubicación | Función |
| --- | --- | --- |
| `stg_transaction_data` | Vista en `dunnhumby_etl.staging`. | Prepara los nombres y tipos de los datos originales de las transacciones. |
| `int_sales_promotional_context` | Vista en `dunnhumby_etl.staging`. | Conserva las líneas de transacción y agrega información promocional obtenida de las demás vistas limpias. |
| Las cuatro dimensiones | Tablas en `Data_warehouse.public`. | Describen los productos, hogares, días y contextos promocionales de las ventas. |
| `fact_sales.sql` | Archivo en `models/facts/`. | Define la consulta con la que dbt actualiza la tabla de hechos. |
| `fact_sales` | Tabla en `Data_warehouse.public`. | Almacena el resultado: las líneas de venta con sus medidas e identificadores. |

### Paso 1. Preparar las ventas en staging

El modelo `int_sales_promotional_context.sql` consulta las vistas limpias y reúne
la información que necesita cada línea de venta. Conserva producto, hogar, día,
cesta, cantidades e importes, y agrega siete atributos promocionales relacionados
con anuncios, campañas, cupones y canjes.

El resultado es una vista en la primera base. Esta preparación debe estar
disponible antes de ejecutar los modelos del warehouse.

### Paso 2. Consultar la vista desde el warehouse

Al ejecutar `fact_sales.sql`, dbt utiliza la conexión `warehouse`, que apunta a
`Data_warehouse`. La consulta obtiene las ventas de la primera base mediante:

```jinja
from {{ staging_view('int_sales_promotional_context', alias='sales') }}
```

`staging_view` utiliza `dblink` para leer la vista de `dunnhumby_etl.staging`.
`sales` es el alias que el SQL usa para referirse a sus columnas. Por ejemplo,
`sales.quantity` es la cantidad que proviene de esa vista.

### Paso 3. Obtener el identificador del contexto promocional

La vista de ventas contiene los siete atributos promocionales. La dimensión
`dim_promotional_context` almacena cada combinación de esos atributos una sola
vez y le asigna un identificador propio.

El modelo de hechos compara los siete valores de cada venta con los de la
dimensión. Cuando coinciden, incorpora su `dim_promotional_context_id`. Así, la
venta queda relacionada con la descripción promocional correspondiente.

La comparación se realiza con un `LEFT JOIN` que compara los siete atributos uno
por uno. Como las vistas reemplazan los `NULL` por textos, la igualdad funciona
en todos los casos.

Varias ventas pueden compartir el mismo contexto y, por tanto, el mismo ID.
Esto no las convierte en una sola venta: cada línea conserva sus propias medidas.
Si alguna venta no encuentra contexto, el `LEFT JOIN` conserva esa línea, pero
la restricción `NOT NULL` de `dim_promotional_context_id` impide completar la carga.

### Paso 4. Obtener los IDs de producto, hogar y día

Cada dimensión tiene un ID propio, distinto del código de Dunnhumby. El modelo
une cada venta con su dimensión usando el código original y toma el ID propio:

| Dimensión | Se une por | Toma |
| --- | --- | --- |
| `dim_product` | `product_id` | `dim_product_id` |
| `dim_household` | `household_id` | `dim_household_id` |
| `dim_time` | `transaction_day` = `dataset_day_number` | `dim_time_id` |

Si una venta no encuentra alguna dimensión, su llave queda `NULL` y la
restricción `NOT NULL` impide completar la carga.

### Paso 5. Seleccionar las columnas y actualizar la tabla

El `SELECT` conserva las medidas y cambia algunos nombres de columnas.

La materialización `cambios` compara ese resultado con `fact_sales` y aplica
solo las diferencias. En la primera ejecución crea la tabla con la identidad
`sale_detail_id` como clave primaria, las cuatro llaves obligatorias y las
claves foráneas declaradas en `foreign_keys`.

## 4. Relaciones con las dimensiones

| Columna de `fact_sales` | Dimensión relacionada | Cómo se obtiene |
| --- | --- | --- |
| `dim_product_id` | `dim_product` | Busca el producto por su código original. |
| `dim_household_id` | `dim_household` | Busca el hogar por su código original. |
| `dim_time_id` | `dim_time` | Busca el día de la venta. |
| `dim_promotional_context_id` | `dim_promotional_context` | Busca la combinación de atributos descrita arriba. |

Las campañas se analizan mediante `household_in_active_campaign` y
`active_campaigns_count` en la dimensión de contexto promocional. Estos campos
permiten comparar el gasto y las compras según la vigencia de campañas asignadas
al hogar, sin atribuir cada venta a una campaña individual.

Una restricción `FOREIGN KEY` comprueba que un identificador no nulo exista en
la dimensión correspondiente. Por ejemplo, el `dim_product_id` de una venta debe
existir en `dim_product`; la restricción evita guardar una referencia a un
producto ausente de esa dimensión.

Los `ref()` a las dimensiones registran las dependencias para que dbt construya
las tablas en el orden necesario. En este modelo aparecen en los `LEFT JOIN` a
las cuatro dimensiones.

`store_id` se conserva como dato de la venta. Actualmente no tiene una dimensión
de tienda relacionada.

## 5. Datos de cada venta

| Columna | Contenido |
| --- | --- |
| `sale_detail_id` | Identificador propio de cada línea de venta; es la clave primaria. |
| `basket_id` | Cesta a la que pertenece la línea. |
| `store_id` | Tienda donde se registró. |
| `transaction_time` | Hora registrada en la fuente, en formato numérico HHMM. |
| `quantity` | Cantidad registrada. |
| `sales_value` | Importe que recibe el comercio por la venta (`SALES_VALUE`). No es lo que pagó el cliente: si usó un cupón del fabricante, pagó `sales_value + coupon_discount` (el descuento es negativo). |
| `retail_discount` | Descuento de la tarjeta de lealtad del comercio (`RETAIL_DISC`). |
| `coupon_discount` | Descuento del cupón del fabricante (`COUPON_DISC`). |
| `coupon_match_discount` | Igualación del cupón del fabricante por parte del comercio (`COUPON_MATCH_DISC`). |

El modelo conserva los importes y los signos preparados en staging. No convierte
los descuentos negativos a positivos ni aplica una escala fija de decimales.

`sale_detail_id` lo genera la tabla (`IDENTITY`) al insertar cada línea y se
conserva en las actualizaciones. La [guía del job](job_etl.md#cómo-se-conservan-los-ids)
explica cuándo una línea conserva su ID y cuándo se inserta como nueva.

## 6. Configuración de los modelos

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
| `unique_key` | Columna o lista de columnas con la que se reconoce cada fila al comparar: `product_id`, `household_id`, `dim_time_id` o los siete atributos de `dim_promotional_context`. Es la clave primaria, salvo que haya `identity_column`; en ese caso queda como restricción única. |
| `identity_column` | ID generado por la tabla y clave primaria: `dim_product_id`, `dim_household_id`, `dim_promotional_context_id` y `sale_detail_id`. Se conserva en las actualizaciones. |
| `not_null_columns`, `unique_columns` | Restricciones adicionales al crear la tabla; por ejemplo, `dataset_day_number` y `calendar_date` únicos en `dim_time`. |
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

## 7. Ejecución

Esta sección corresponde al paso 9 del [README](../README.md). Requiere los
pasos 1 a 8 del [README](../README.md) completos: vistas de staging,
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

## 8. Verificación y validación de resultados

Esta validación corresponde al paso 10 del [README](../README.md).

### Revisar las dimensiones

En pgAdmin, abrir Query Tool conectado a **`Data_warehouse`**:

```sql
select * from public.dim_product limit 10;
select * from public.dim_household limit 10;
select * from public.dim_time limit 10;
select * from public.dim_promotional_context limit 10;
```

### Ejecutar las pruebas

Para ejecutar las pruebas sin modificar las tablas:

```powershell
python -m dotenv -f .env run -- dbt test `
    --profiles-dir . `
    --target warehouse `
    --select path:models/dimensions path:models/facts
```

Las diez pruebas definidas en `models/facts/facts.yml` revisan:

- Que `sale_detail_id` sea único y no sea nulo.
- Que producto, hogar, día y contexto tengan un ID no nulo.
- Que los IDs no nulos existan en las cuatro dimensiones.

`PASS` indica que una prueba pasó. Si aparece `FAIL` o `ERROR`, revisar el
mensaje antes de continuar. Estas pruebas comprueban claves y relaciones;
no comparan por sí solas todos los importes y líneas con staging.

### Revisar las ventas

Para ver las ventas en pgAdmin, abrir Query Tool conectado a **`Data_warehouse`**:

```sql
-- Mostrar diez líneas de venta para revisar sus columnas.
SELECT *
FROM public.fact_sales
LIMIT 10;
```

Para consultar cuántas líneas quedaron almacenadas, ejecutar en la misma base:

```sql
SELECT count(*) AS filas_hechos
FROM public.fact_sales;
```

Para comparar el conteo, ejecutar esta otra consulta conectado a
**`dunnhumby_etl`**, sin haber cambiado staging entre ambas consultas:

```sql
SELECT count(*) AS filas_origen
FROM staging.stg_transaction_data;
```

Los dos conteos deben coincidir: se espera una fila de hechos por cada línea
de transacción. Coincidir en conteo no demuestra por sí solo que todos los
valores sean iguales; es una comprobación adicional a las pruebas de relaciones.
