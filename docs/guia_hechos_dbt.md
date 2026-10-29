# Cómo se crea la tabla de hechos con dbt

`fact_sales` guarda las ventas y las relaciona con las cuatro dimensiones.
El modelo que la crea es [fact_sales.sql](../models/facts/fact_sales.sql).
La tabla resultante queda en **`Data_warehouse.public.fact_sales`**.

Las medidas y dimensiones permiten elaborar consultas de gerencia, ventas,
marketing, promociones y análisis comercial.

## 1. Qué información representa cada fila

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

## 2. Fuentes y construcción de la tabla

La construcción utiliza los siguientes objetos, cada uno con una responsabilidad:

| Objeto | Ubicación | Función |
| --- | --- | --- |
| `stg_transaction_data` | Vista en `dunnhumby_etl.staging`. | Prepara los nombres y tipos de los datos originales de las transacciones. |
| `int_sales_promotional_context` | Vista en `dunnhumby_etl.staging`. | Conserva las líneas de transacción y agrega información promocional obtenida de las demás vistas limpias. |
| Las cuatro dimensiones | Tablas en `Data_warehouse.public`. | Describen los productos, hogares, días y contextos promocionales de las ventas. |
| `fact_sales.sql` | Archivo en `models/facts/`. | Define la consulta y las restricciones con las que dbt construye la tabla de hechos. |
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
dimensión. Cuando coinciden, incorpora su `promotional_context_id`. Así, la venta
queda relacionada con la descripción promocional correspondiente.

La comparación se realiza con un `LEFT JOIN`. El código reúne los siete valores
con `jsonb_build_array` para compararlos juntos, incluidos los `NULL`. El arreglo
se utiliza durante la consulta y no se almacena en la tabla final.

Varias ventas pueden compartir el mismo contexto y, por tanto, el mismo ID.
Esto no las convierte en una sola venta: cada línea conserva sus propias medidas.
Si alguna venta no encuentra contexto, el `LEFT JOIN` conserva esa línea, pero
la restricción `NOT NULL` de `promotional_context_id` impide completar la carga.

### Paso 4. Seleccionar las columnas y crear la tabla

El `SELECT` conserva las medidas y los identificadores de origen, cambia algunos
nombres de columnas y calcula `sale_detail_id`. Para producto y hogar se
conservan los IDs originales; para tiempo se utiliza el día de la transacción.
El `SELECT` no necesita unir esas tres dimensiones para recuperar sus IDs.

La configuración `materialized='table'` indica a dbt que guarde el resultado
como tabla. Después, los `post_hook` agregan la clave primaria, configuran la
identidad y establecen las claves foráneas hacia las cuatro dimensiones.

El resultado es `Data_warehouse.public.fact_sales`. Su construcción se realiza
desde el modelo dbt; no requiere un script de copia de tablas.

## 3. Relaciones con las dimensiones

| Columna de `fact_sales` | Dimensión relacionada | Cómo se obtiene |
| --- | --- | --- |
| `product_id` | `dim_product` | Conserva el ID del producto vendido. |
| `household_id` | `dim_household` | Conserva el ID del hogar que compró. |
| `time_id` | `dim_time` | Usa el número de día de la venta. |
| `promotional_context_id` | `dim_promotional_context` | Busca la combinación de atributos descrita arriba. |

Las campañas se analizan mediante `household_in_active_campaign` y
`active_campaigns_count` en la dimensión de contexto promocional. Estos campos
permiten comparar el gasto y las compras según la vigencia de campañas asignadas
al hogar, sin atribuir cada venta a una campaña individual.

Una restricción `FOREIGN KEY` comprueba que un identificador no nulo exista en
la dimensión correspondiente. Por ejemplo, el `product_id` de una venta debe
existir en `dim_product`; la restricción evita guardar una referencia a un
producto ausente de esa dimensión.

Los `ref()` a las dimensiones registran las dependencias para que dbt construya
las tablas en el orden necesario. En este modelo aparecen en las instrucciones
que agregan las claves foráneas y en la consulta al contexto promocional.

`store_id` se conserva como dato de la venta. Actualmente no tiene una dimensión
de tienda relacionada.

## 4. Datos de cada venta

| Columna | Contenido |
| --- | --- |
| `sale_detail_id` | Identificador propio de cada línea de venta; es la clave primaria. |
| `basket_id` | Cesta a la que pertenece la línea. |
| `store_id` | Tienda donde se registró. |
| `transaction_time` | Hora registrada en la fuente, en formato numérico HHMM. |
| `quantity` | Cantidad registrada. |
| `sales_value` | Importe de la venta. |
| `retail_discount` | Descuento del comercio. |
| `coupon_discount` | Descuento de cupón. |
| `manufacturer_coupon_discount` | Valor de `coupon_match_discount`, con el nombre definido para el warehouse. |

El modelo conserva los importes y los signos preparados en staging. No convierte
los descuentos negativos a positivos ni aplica una escala fija de decimales.

`sale_detail_id` se calcula inicialmente con `row_number()`. Después, la macro
`initialize_identity` configura `IDENTITY` y ajusta la secuencia para futuras
inserciones. Una reconstrucción puede asignar otros IDs a las mismas líneas.

## 5. Ejecución del modelo

Primero deben existir las vistas de la primera base, las conexiones y los permisos.
La [guía de dimensiones](guia_dimensiones_dbt.md#4-ejecución-del-flujo)
explica esa preparación y sus comandos.

Ejecutar desde PowerShell, en la raíz del proyecto:

```powershell
python -m dotenv -f .env run -- dbt build `
    --profiles-dir . `
    --target warehouse `
    --select path:models/dimensions path:models/facts
```

Es un solo comando dividido en varias líneas para facilitar su lectura. En
PowerShell, el acento grave al final de cada línea indica que continúa en la
siguiente; no debe tener espacios después. Se puede copiar el bloque completo.

`--target warehouse` selecciona la conexión a la segunda base. `--select` incluye
los modelos de dimensiones y hechos, y `dbt build` construye las tablas y ejecuta
sus pruebas. El prefijo con `dotenv` carga las variables del archivo `.env`.

Este comando reconstruye las cuatro dimensiones y hechos, y ejecuta las pruebas
asociadas. Es la misma ejecución completa documentada en la guía de dimensiones;
se realiza una vez por actualización del modelo estrella.

La carga es completa: dbt vuelve a construir las tablas con las consultas de
los modelos. No agrega solamente las ventas nuevas. Se reconstruyen juntas
porque los IDs del contexto promocional pueden cambiar.

## 6. Validación de resultados

Para ejecutar las pruebas sin reconstruir las tablas:

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
