# Actualización: IDs propios, códigos según Kimball y la guía de dunnhumby, sincronización de staging y job de madrugada

Esta guía explica qué cambió en el proyecto y qué tiene que ejecutar cada
integrante para que su base de datos y su job queden iguales. Reúne dos
actualizaciones:

- **IDs propios, fechas, nulos y códigos** según Kimball y la guía de dunnhumby.
- **Puntos 3.1 y 3.2:** sincronización de staging con el origen y job de madrugada.

Hay que seguir los pasos **una sola vez**, en orden.

## 1. Qué cambió

### Staging

| Vista | Cambio |
| --- | --- |
| `stg_transaction_data` | Nueva columna `transaction_date`: fecha base `2004-01-01` + (`DAY` − 1). Es una fecha supuesta, porque Dunnhumby no publica fechas reales. |
| `stg_product` | Los textos vacíos ahora dicen `'not available'` en lugar de `NULL`. |
| `stg_causal_data` | Nuevas columnas `display_description` y `mailer_description`, con el significado de cada código según la guía de Dunnhumby (ver la [sección 2](#2-códigos-de-display-y-mailer)). Los códigos originales `display` y `mailer` se conservan. |
| `int_household` (nueva) | Reúne los hogares y su demografía. Antes esto lo hacía `dim_household`. Los hogares sin perfil dicen `'No demographic profile'`. El estado civil se traduce: `A` → `'Married'`, `B` → `'Single'`, `U` → `'Unknown'` (ver la [sección 3](#3-revisión-contra-la-guía-oficial-de-dunnhumby)). |
| `int_time` (nueva) | Calendario de cada día, basado en la DIM_TIEMPO del profesor: año, trimestre, mes, semana, día de la semana y sus nombres. |
| `int_sales_promotional_context` | Los `NULL` y `TRUE`/`FALSE` ahora son textos: `'Promotion'`, `'Undetermined'`, `'In campaign'`, `'Coupon available'`, `'Redeemed'`, etc. `display_type` y `mailer_type` ahora llevan descripciones (`'In-aisle'`) en lugar de listas de códigos (`["7"]`). `product_associated_with_coupon` tiene un valor nuevo, `'Coupon received'`, para las campañas TypeB y TypeC. |

### Warehouse

Cada dimensión tiene ahora **su propio ID** (llave primaria), y el código de
Dunnhumby se conserva como una columna más:

| Dimensión | ID propio | Código original |
| --- | --- | --- |
| `dim_product` | `dim_product_id` (1, 2, 3…) | `product_id` |
| `dim_household` | `dim_household_id` (1, 2, 3…) | `household_id` |
| `dim_time` | `dim_time_id` (fecha como 20040101) | `dataset_day_number` |
| `dim_promotional_context` | `dim_promotional_context_id` (1, 2, 3…) | — |

**Regla de nombres:** `_id` solo = código de Dunnhumby; `dim_..._id` = ID del
warehouse.

Otros cambios:

- `fact_sales` usa los cuatro `dim_..._id` como llaves.
- En `fact_sales`, la columna `manufacturer_coupon_discount` ahora se llama
  `coupon_match_discount`, porque guarda la igualación del cupón que hace el
  comercio, no el descuento del fabricante (ver la
  [sección 3](#3-revisión-contra-la-guía-oficial-de-dunnhumby)).
- Las dimensiones solo insertan lo que traen sus vistas; las uniones y los
  cálculos se hacen en staging.
- `dim_time` tiene ahora 17 columnas de calendario, todas obligatorias.
- `dim_promotional_context` ya no tiene la columna `context_key`, y
  `display_type` y `mailer_type` muestran descripciones legibles.
- Ninguna dimensión tiene `NULL`.

El detalle está en [tratamiento de nulos](tratamiento_nulos.md) y en la
[guía del modelo estrella](guia_modelo_estrella_dbt.md) (dimensiones y hechos).

### Punto 3.2: sincronizar origen → staging

Antes, las copias de `staging` se hacían una sola vez con
`copiar_tablas_a_staging.sql`. Si cambiaba algo en `public`, nunca llegaba al
warehouse.

Ahora dbt crea y actualiza las copias con los modelos de
`models/sincronizacion/`. En cada ejecución del job compara `public` con
`staging` y aplica solo las diferencias:

| Cambio en `public` | Qué pasa en `staging` |
| --- | --- |
| Registro nuevo | Se inserta. |
| Registro modificado | Se borra la versión anterior y se inserta la nueva. |
| Registro eliminado | Se borra. |

El flujo completo queda así:

```text
public → staging (copias) → vistas stg_ → dimensiones y hechos → Excel
```

Cambios en el repositorio:

- `copiar_tablas_a_staging.sql` se eliminó: la copia la hace dbt.
- Las vistas `stg_` leen las copias con `ref()` en lugar de
  `source('dunnhumby_raw', ...)`. La fuente `dunnhumby_raw` ya no existe.
- El job sincroniza staging antes de actualizar el warehouse. Si la
  sincronización falla, el warehouse no se toca.

### Punto 3.1: job en la madrugada

| | Antes | Ahora |
| --- | --- | --- |
| Nombre | `Dunnhumby_ETL_cada_2_horas` | `Dunnhumby_ETL_madrugada` |
| Horario | Cada dos horas | Todos los días a las 2:00 a. m. |

El job tarda unos 20 minutos, así que en la mañana Excel ya tiene los datos del
día anterior. La computadora debe estar encendida a esa hora; si está apagada,
el job corre cuando se vuelve a encender.

## 2. Códigos de display y mailer

### El problema

`causal_data` indica con códigos si un producto estuvo en exhibición o en el
folleto. Antes, `dim_promotional_context` guardaba esos códigos tal cual, como
lista JSON: quien analizaba en Excel veía `["7"]` o `["H"]` sin saber qué
significaban.

Según Kimball, los atributos de una dimensión deben ser descripciones que el
usuario entienda, no códigos. Por eso ahora se traducen:

| dim_promotional_context_id | display_type antes | display_type ahora | mailer_type ahora |
| ---: | --- | --- | --- |
| 1 | `["7"]` | In-aisle | Interior page feature |
| 2 | `["0"]` | Not on display | Front page feature |
| 3 | `["0","3"]` | Front end cap + Not on display | Wrap front feature |

Reglas:

- **Dos códigos en la misma venta.** Algunas combinaciones de producto, tienda
  y semana tienen dos códigos. Las descripciones se unen con `' + '`,
  en orden alfabético, para que el texto sea el mismo en cada ejecución.
- **Ventas sin datos causales.** Siguen como `'No causal data'`.
- **Código desconocido.** Si la fuente trajera un código que no está en las
  tablas, quedaría como `'Unknown code X'`, nunca como `NULL`. Hoy no ocurre.
- La estructura de la tabla no cambia por esto: mismas columnas, mismos
  nombres.

### De dónde salen las descripciones

Salen de la guía oficial del dataset, **The Complete Journey User Guide**,
publicada por dunnhumby (2014), página 6, tabla *causal_data*.

- **Sitio oficial:** [dunnhumby Source Files](https://www.dunnhumby.com/source-files/),
  sección *The Complete Journey*. Allí se descarga el dataset; el sitio no
  publica la guía como enlace aparte.
- **Copia de consulta de la guía (PDF):**
  [dunnhumby - The Complete Journey User Guide.pdf](https://github.com/Lanbig/CSC465-visualization-project/blob/master/Dataset/dunnhumby%20-%20The%20Complete%20Journey%20User%20Guide.pdf),
  en un repositorio público de GitHub.

**Por qué se usa esta guía.** Es la documentación que dunnhumby, el dueño de
los datos, entrega con el dataset, y es el único lugar donde se define qué
significa cada código. Si las descripciones se inventaran o se tomaran de otra
fuente, el warehouse mostraría interpretaciones propias como si fueran datos.

**Cómo se sabe que es la guía correcta.** Se comparó con los datos cargados en
`dunnhumby_etl`:

| Lo que dice la guía | Lo que tienen nuestros datos | ¿Coincide? |
| --- | --- | --- |
| Encabezado *dunnhumby · Source Files*, título *The Complete Journey* | Es el dataset que usa el proyecto | Sí |
| `causal_data` tiene PRODUCT_ID, STORE_ID, WEEK_NO, DISPLAY y MAILER | Mismas columnas | Sí |
| 2 500 hogares y 92 353 productos | `dim_household` = 2 500, `dim_product` = 92 353 | Sí |
| `causal_data` cubre 68 377 productos | 68 377 productos distintos | Sí |
| Display: 0–7, 9 y A (no existe el 8) | Exactamente esos 10 códigos | Sí |
| Mailer: 0, A, C, D, F, H, J, L, P, X y Z | Exactamente esos 11 códigos | Sí |
| Ejemplo de la página 10: producto 72717, tienda 299, semana 12 → display 7, mailer A | Misma fila en `causal_data` | Sí |

### Códigos de display

Dónde se exhibió el producto dentro de la tienda.

| Código | Descripción | Significado |
| --- | --- | --- |
| 0 | Not on display | Sin exhibición |
| 1 | Store front | Frente de la tienda |
| 2 | Store rear | Fondo de la tienda |
| 3 | Front end cap | Cabecera de góndola delantera |
| 4 | Mid-aisle end cap | Cabecera a mitad de pasillo |
| 5 | Rear end cap | Cabecera trasera |
| 6 | Side-aisle end cap | Cabecera de pasillo lateral |
| 7 | In-aisle | Dentro del pasillo |
| 9 | Secondary location display | Exhibición en ubicación secundaria |
| A | In-shelf | En el estante |

### Códigos de mailer

Cómo apareció el producto en el folleto semanal.

| Código | Descripción | Significado |
| --- | --- | --- |
| 0 | Not on ad | No salió en el folleto |
| A | Interior page feature | Destacado en página interior |
| C | Interior page line item | Línea simple en página interior |
| D | Front page feature | Destacado en portada |
| F | Back page feature | Destacado en contraportada |
| H | Wrap front feature | Destacado en el frente del encarte |
| J | Wrap interior coupon | Cupón en el interior del encarte |
| L | Wrap back feature | Destacado en el reverso del encarte |
| P | Interior page coupon | Cupón en página interior |
| X | Free on interior page | Gratis en página interior |
| Z | Free on front page, back page or wrap | Gratis en portada, contraportada o encarte |

Las descripciones se escriben en inglés, como en la guía y como el resto de los
textos del proyecto.

### Dónde se traduce y por qué

La traducción se hace en las vistas, no directamente en el warehouse:

```text
causal_data (fuente)            display = '7'
        ↓
stg_causal_data                 display = '7', display_description = 'In-aisle'   ← aquí se traduce
        ↓
int_sales_promotional_context   display_type = 'In-aisle'                          ← agrupa descripciones
        ↓  dbt build --target warehouse
dim_promotional_context         display_type = 'In-aisle'                          ← se ve en Excel
```

- **No con un `UPDATE` en el warehouse.** El job recarga desde las vistas en
  cada ejecución: volvería a traer `["7"]`, no lo encontraría en la dimensión y
  lo insertaría como combinación nueva, con otro ID. Además, el cambio no
  quedaría en Git.
- **En `stg_causal_data`.** Es donde están los códigos. Las descripciones se
  agregan como columnas nuevas, así que staging sigue conservando el dato
  original y la detección de promociones sigue usando los códigos.
- **Con un `CASE` y no con un seed.** Son 21 códigos fijos. Un seed (CSV
  cargado por dbt) obligaría a cambiar los comandos de este documento y del
  job, que solo seleccionan `path:models/...`.

## 3. Revisión contra la guía oficial de dunnhumby

Con la guía en mano, se revisó todo el proyecto (vistas, dimensiones, hechos y
documentos) para confirmar que respeta lo que dunnhumby define. Se encontró un
error y tres mejoras, y ya están aplicados.

### Error corregido: el descuento de igualación del cupón

La guía (página 4) define tres descuentos:

| Columna fuente | Según la guía | Columna en `fact_sales` |
| --- | --- | --- |
| `RETAIL_DISC` | Descuento de la tarjeta de lealtad del comercio | `retail_discount` |
| `COUPON_DISC` | Descuento del cupón del **fabricante** | `coupon_discount` |
| `COUPON_MATCH_DISC` | Igualación del cupón del fabricante por parte del **comercio** | `coupon_match_discount` |

Antes, `COUPON_MATCH_DISC` se cargaba con el nombre
`manufacturer_coupon_discount` ("descuento del fabricante"), que dice lo
contrario de la guía. Ahora se llama `coupon_match_discount`.

### Mejora 1: estado civil legible

La guía (página 3) define `MARITAL_STATUS_CODE`: **A = Married, B = Single,
U = Unknown**. Antes `dim_household.marital_status` guardaba la letra; ahora
guarda la descripción. Es el mismo criterio de Kimball que se aplicó a display y
mailer. La traducción se hace en `int_household`.

### Mejora 2: qué es `sales_value`

La guía (página 4) aclara que `sales_value` es **lo que recibe el comercio**,
no lo que pagó el cliente. Si el cliente usó un cupón del fabricante, pagó
`sales_value + coupon_discount` (el descuento es negativo). La [guía del modelo estrella](guia_modelo_estrella_dbt.md)
y la de [cobertura](cobertura_necesidades.md) ya lo explican así. No cambia ningún dato.

### Mejora 3: cupones recibidos en campañas TypeB y TypeC

La guía (página 5) dice que:

- en las campañas **TypeA**, cada hogar recibe solo 16 cupones del total, y no
  se sabe cuáles;
- en las campañas **TypeB y TypeC**, cada hogar participante recibe **todos**
  los cupones de la campaña.

Por eso `product_associated_with_coupon` tiene ahora tres valores:

| Valor | Significado |
| --- | --- |
| `'Coupon received'` | El hogar participa en una campaña TypeB o TypeC vigente que tiene cupón para ese producto: se sabe que tenía el cupón. |
| `'Coupon available'` | Hay un cupón vigente para el producto, pero no se sabe si el hogar lo recibió (por ejemplo, TypeA). |
| `'No coupon'` | No hay cupón vigente para el producto. |

Con este valor nuevo, `dim_promotional_context` pasa de 1 165 a 1 331
combinaciones.

### Lo que coincide con la guía

Se compararon las cifras y el caso de estudio de la guía con los datos cargados
en `dunnhumby_etl`:

| Guía | Nuestros datos | ¿Coincide? |
| --- | --- | --- |
| 801 hogares con demografía | 801 | Sí |
| 2 500 hogares y 92 339 productos en transacciones | 2 500 y 92 339 | Sí |
| 92 353 productos | 92 353 | Sí |
| `WEEK_NO` de 1 a 102 | 1 a 102 | Sí |
| 1 584 hogares en 30 campañas, tipos TypeA, TypeB y TypeC | 1 584 y 30; A, B y C | Sí |
| 1 135 cupones para 44 133 productos | 1 135 y 44 133 | Sí |
| 434 hogares canjearon 556 cupones | 434 y 556 | Sí |
| 68 377 productos en `causal_data` | 68 377 | Sí |
| `BRAND` es Private o National | Solo esos dos valores | Sí |
| Hogar 208: 45-54, U, 50-74K, Homeowner, 8 campañas (5 TypeA y 3 TypeB) | Igual | Sí |
| Campaña 22: días 624 a 656, 21 cupones; el cupón 51800000050 aplica a 38 productos | Igual | Sí |
| Compra del hogar 208, día 654, producto 1017772: 1,33, cupón −0,5, igualación −0,5 | Igual | Sí |
| Producto 72717, tienda 421, semana 12: display 2, mailer A | Igual | Sí |

**Única diferencia:** la guía muestra 7 canjes del hogar 208 y los datos tienen
6. El CSV original (`database/coupon_redempt.csv`) también tiene 6: la tabla de
la guía repite una fila (día 606, mismo cupón). No es un error del proyecto.

## 4. Qué deben ejecutar

Todo se ejecuta en PowerShell desde la carpeta del proyecto, salvo los pasos
de pgAdmin.

### Paso 1. Traer los cambios

```powershell
git pull
```

Si trabajan en otra rama, traer los cambios de la rama `seidy` o de `main`,
según dónde estén.

### Paso 2. Activar el entorno

```powershell
.\venv\Scripts\Activate.ps1
```

Debe aparecer `(venv)` al inicio de la línea.

### Paso 3. Apagar el job

En pgAdmin: **pgAgent Jobs → Dunnhumby_ETL_cada_2_horas → Properties**,
desactivar **Enabled?** y pulsar **Save**. Si el job ya se llama
`Dunnhumby_ETL_madrugada`, desactivar ese.

Si el job corre durante los siguientes pasos, falla o deja datos a medias.

### Paso 4. Sincronizar staging y recrear las vistas

```powershell
python -m dotenv -f .env run -- dbt build `
    --profiles-dir . `
    --target dev `
    --select path:models/sincronizacion path:models/staging path:models/intermediate
```

**Resultado esperado:** `ERROR=0`. Tarda unos 4 minutos; `causal_data` es la
más lenta. Solo la parte de vistas (`path:models/staging path:models/intermediate`)
da `PASS=35 WARN=0 ERROR=0` y tarda menos de un minuto.

Si ya tenían las copias en staging, cada tabla debe mostrar
`0 filas borradas, 0 filas insertadas`. Si no las tenían, dbt las crea.

### Paso 5. Borrar las tablas del warehouse

La carga no puede cambiar la estructura de una tabla que ya existe, por eso hay
que borrarlas (por ejemplo, `fact_sales` cambió `manufacturer_coupon_discount`
por `coupon_match_discount`). Además, la carga es incremental: si no se borrara
`dim_promotional_context`, conservaría las filas viejas con `["7"]` y
agregaría otras nuevas con `In-aisle`. En `main` también entraron la traducción
de `display` y `mailer` y otros cambios en las dimensiones, por eso hay que
recrear las tablas una vez.

En pgAdmin, Query Tool conectado a **`Data_warehouse`**:

```sql
DROP TABLE public.fact_sales;
DROP TABLE public.dim_product;
DROP TABLE public.dim_household;
DROP TABLE public.dim_time;
DROP TABLE public.dim_promotional_context;
```

`fact_sales` va primero porque tiene las llaves foráneas hacia las dimensiones.

### Paso 6. Cargar el warehouse

```powershell
python -m dotenv -f .env run -- dbt build `
    --profiles-dir . `
    --target warehouse `
    --select path:models/dimensions path:models/facts
```

**Resultado esperado:** `PASS=27 WARN=0 ERROR=0`. Tarda entre 10 y 15
minutos; `dim_promotional_context` y `fact_sales` son las más lentas.

### Paso 7. Comprobar

En Query Tool conectado a **`Data_warehouse`**:

```sql
SELECT 'dim_product' AS tabla, count(*) FROM dim_product
UNION ALL SELECT 'dim_household', count(*) FROM dim_household
UNION ALL SELECT 'dim_time', count(*) FROM dim_time
UNION ALL SELECT 'dim_promotional_context', count(*) FROM dim_promotional_context
UNION ALL SELECT 'fact_sales', count(*) FROM fact_sales;
```

| Tabla | Filas esperadas |
| --- | ---: |
| `dim_product` | 92 353 |
| `dim_household` | 2 500 |
| `dim_time` | 711 |
| `dim_promotional_context` | 1 331 |
| `fact_sales` | 2 595 732 |

Si `dim_promotional_context` muestra 1 165 filas, es el conteo de la versión
anterior, sin el valor `'Coupon received'` (ver la
[sección 3](#3-revisión-contra-la-guía-oficial-de-dunnhumby)): revisar que el
paso 4 se ejecutó con los cambios nuevos.

Y para comprobar las descripciones:

```sql
SELECT display_type, count(*)
FROM dim_promotional_context
GROUP BY display_type
ORDER BY 2 DESC;
```

Deben aparecer textos como `In-aisle` o `Front end cap`, y ningún valor con
corchetes.

Y para comprobar los cambios de la [sección 3](#3-revisión-contra-la-guía-oficial-de-dunnhumby):

```sql
SELECT marital_status, count(*) FROM dim_household GROUP BY 1 ORDER BY 1;
SELECT product_associated_with_coupon, count(*) FROM dim_promotional_context GROUP BY 1 ORDER BY 1;
SELECT sum(coupon_match_discount) FROM fact_sales;
```

- `marital_status` debe mostrar `Married`, `Single`, `Unknown` y
  `No demographic profile`, sin letras sueltas.
- `product_associated_with_coupon` debe incluir `Coupon received`.
- La última consulta debe funcionar; si dice que la columna no existe,
  `fact_sales` no se borró en el paso 5.

### Paso 8. Registrar el job con el nuevo horario

Requiere haber configurado pgAgent antes (debe existir
`logs/jobs/pgagent_ejecutar.cmd`). Si nunca lo configuraron, seguir la
[instalación del job](job_etl.md#3-instalación) completa en lugar de este paso.

Abrir PowerShell **como administrador**, ir a la carpeta del proyecto, activar
el mismo entorno de Python con el que configuraron pgAgent y ejecutar:

```powershell
.\scripts\registrar_pgagent.ps1
```

Si muestra `No se pudo leer .env` o `Falta dotenv.exe`, el PowerShell de
administrador encontró otro dbt. Indicar la ruta del dbt que usa el job, por
ejemplo:

```powershell
.\scripts\registrar_pgagent.ps1 -DbtExecutable 'C:\ruta\al\entorno\Scripts\dbt.exe'
```

El script:

- Renombra el job a `Dunnhumby_ETL_madrugada` y lo programa a las 2:00 a. m.
  Convierte la hora local a la zona del servidor, que puede ser GMT.
- Vuelve a dar al servicio de pgAgent permiso de lectura sobre los archivos
  del proyecto.
- Deja el job **desactivado** para probarlo primero.

Para otra hora, agregar `-Hora`, por ejemplo `.\scripts\registrar_pgagent.ps1 -Hora 3`.

### Paso 9. Encender el job

En pgAdmin: **pgAgent Jobs → Dunnhumby_ETL_madrugada → Properties**, activar
**Enabled?** en el job y en el horario **Diario 02:00 hora local**, y pulsar
**Save**.

Si pgAdmin ya estaba abierto, pulsar **Refresh** para ver el nombre nuevo.

### Paso 10. Probar el job

Clic derecho en **Dunnhumby_ETL_madrugada → Run now**. También se puede probar
a mano desde PowerShell:

```powershell
.\logs\jobs\pgagent_ejecutar.cmd
```

Este comando se ejecuta en una ventana oculta. Tarda unos 20 minutos. No
ejecutarlo dos veces: la segunda se detiene con *"Hay otra ejecución dbt
activa"*.

Al terminar, `logs/jobs/ultima_ejecucion.json` debe decir
`"estado": "CORRECTO"`.

### Paso 11. Excel

Si ya tenían un libro conectado al warehouse:

1. **Datos → Actualizar todo.**
2. En el Modelo de datos, rehacer las relaciones de `fact_sales` con cada
   dimensión usando los IDs nuevos: `dim_product_id`, `dim_household_id`,
   `dim_time_id` y `dim_promotional_context_id`.
3. Para períodos, usar `calendar_year`, `quarter_name` o `month_name` de
   `dim_time`. Para que los meses salgan en orden, ordenar `month_name` por
   `calendar_month`.
4. Si alguna tabla dinámica usaba `manufacturer_coupon_discount`, cambiarla por
   `coupon_match_discount`.

## 5. Si algo falla

| Mensaje | Causa | Solución |
| --- | --- | --- |
| `Permission denied: ...dbt_project.yml` en el log del job | El servicio perdió el permiso de lectura al cambiar el archivo. | Repetir el paso 8, o ejecutar `icacls dbt_project.yml /grant '*S-1-5-19:(RX)'`. |
| `Hay otra ejecución dbt activa` | El job ya está corriendo. | Esperar a que termine; no ejecutarlo dos veces. |
| `Las columnas de staging.<tabla> no coinciden con el origen` | Cambiaron las columnas de una tabla en `public`. | Revisar el cambio en `public` antes de volver a ejecutar. |
| `Job existente ajeno o en ejecucion` al registrar | El job está corriendo. | Esperar a que termine y repetir el paso 8. |

Más detalles en [capa staging](capa_staging.md) y en la
[guía del job](job_etl.md) (ejecución y configuración de pgAgent).

## 6. Decisiones que deben conocer

- **Fecha base `2004-01-01`.** Es un supuesto del proyecto; conviene
  mencionarlo así en el documento escrito. Para cambiarla, se modifica
  `fecha_base` en `stg_transaction_data.sql` y se repiten los pasos 4 a 7.
- **Textos en inglés**, igual que las columnas y los valores de la fuente.
- **`'No promotion'` no aparece** en los datos actuales: la fuente nunca registra
  una ausencia explícita de promoción, así que las ventas sin datos causales
  quedan como `'Undetermined'`.
- **Códigos de display y mailer traducidos** con la guía oficial de dunnhumby
  (ver la [sección 2](#2-códigos-de-display-y-mailer)). En la primera versión
  de esta actualización quedaba pendiente decidir si los códigos de
  `display_type` y `mailer_type` (por ejemplo, `["0","3"]`) se traducían a una
  descripción legible; esa decisión ya se tomó y se aplicó. Al citarla en el
  documento escrito: *dunnhumby (2014). The Complete Journey User Guide.
  dunnhumby Source Files.*
- **Todo el modelo se revisó contra esa guía** (ver la
  [sección 3](#3-revisión-contra-la-guía-oficial-de-dunnhumby)): estado civil
  traducido, `coupon_match_discount` con su nombre correcto, `sales_value`
  explicado como ingreso del comercio y `'Coupon received'` para TypeB y TypeC.
