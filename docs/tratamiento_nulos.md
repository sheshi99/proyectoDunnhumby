# Tratamiento de datos nulos y desconocidos

## Procedimiento realizado

Para realizar el tratamiento de valores faltantes, primero revisamos los datos
fuente por medio de consultas de calidad. Con los resultados obtenidos, definimos
las siguientes reglas:

- **NULL:** el dato es desconocido o no existe información suficiente. Se
  aplica porque reemplazarlo por un supuesto modificaría el significado real
  del dato.
- **0:** se comprobó que la cantidad de registros o campañas es cero. Se
  aplica cuando la ausencia de coincidencias representa efectivamente ausencia
  de elementos, no desconocimiento.
- **FALSE:** se comprobó que una condición no se cumple. Se aplica solamente
  cuando existe evidencia explícita o el conteo permite determinar el resultado.
- **Texto original:** se conserva cuando la fuente registró una categoría como
  `Unknown` o `None/Unknown`. Se aplica porque esos textos son valores reales
  de origen y pueden representar una categoría distinta de ausencia.

Estas reglas se establecieron para evitar modificar datos que pudieran tener
un significado diferente. También decidimos conservar los ceros y descuentos
negativos, ya que pueden representar información válida dentro del dataset y
no se encontraron evidencias suficientes para eliminarlos o convertirlos.

## Justificación de las reglas

Para aplicar las reglas tuvimos en cuenta los siguientes criterios:

1. **No eliminar filas por datos incompletos.** La pérdida de un atributo
   descriptivo no convierte en inválida una transacción. Por ello, los hogares
   sin demografía y las ventas sin coincidencia promocional se mantienen.

2. **Distinguir ausencia desconocida de ausencia comprobada.** Utilizamos
   `NULL` cuando existe desconocimiento, mientras que `0` o `FALSE` indican que la ausencia pudo
   comprobarse mediante los datos disponibles.

3. **Conservar la trazabilidad de la fuente.** Las categorías originales y los
   signos negativos no se modifican sin una regla de negocio que lo justifique.

4. **Evitar introducir datos ficticios.** Reemplazar un atributo desconocido
   por `Desconocido`, `Sin información` o una categoría arbitraria podría
   afectar conteos y análisis posteriores.

5. **Resolver cada dato en la capa correspondiente.** Realizamos la limpieza
   básica en staging, los indicadores derivados se calculan en la vista
   intermedia y las dimensiones reciben valores preparados sin volver a asumir
   reglas de negocio.

## Resumen de decisiones por capa

| Capa | Qué se hizo | Justificación |
|---|---|---|
| Staging | Se convirtieron cadenas vacías en `NULL` y se conservaron valores válidos. | Permite normalizar datos faltantes sin eliminar registros ni modificar valores conocidos. |
| Vista intermedia | Se calculó el contexto promocional, campañas y evidencia. | Consolida relaciones entre ventas y datos promocionales antes de construir el hecho. |
| Dimensiones | Se conservaron entidades conocidas y atributos desconocidos como `NULL`. | Evita inventar atributos descriptivos y mantiene la integridad del modelo estrella. |
| Data Warehouse | Se construyó un esquema estrella con hechos, dimensiones y llaves. | Permite relacionar eventos con sus atributos y realizar análisis eficientes. |

# 1. Trabajo realizado en las vistas de staging

Las vistas de staging tienen como función limpiar los datos y dejarlos
preparados antes de crear las dimensiones.

## 1.1. Productos

La revisión de calidad encontró campos descriptivos que contenían espacios
vacíos. Para corregirlos se utilizó la vista
[stg_product.sql](../models/staging/stg_product.sql).

Después de eliminar los espacios externos, las cadenas vacías se convirtieron
en `NULL`:

```sql
nullif(btrim("DEPARTMENT"), '')
```

La misma regla se aplicó a categoría, subcategoría y tamaño.

Ejemplo:

```text
"   "       → NULL
"groceries" → "groceries"
```

Las etiquetas `NO COMMODITY DESCRIPTION` y `NO SUBCOMMODITY DESCRIPTION`
también se conservaron, porque son textos registrados por la fuente.

## 1.2. Demografía

La vista [stg_hh_demographic.sql](../models/staging/stg_hh_demographic.sql)
conservó las categorías originales `Unknown` y `None/Unknown`.

Estas categorías son diferentes de un `NULL`:

```text
Unknown       = categoría registrada por el sistema
None/Unknown  = categoría registrada por el sistema
NULL          = no existe información disponible
```

## 1.3. Transacciones

La revisión de [transaction_data.sql](../scripts/sql/RevisionCalidad/transaction_data.sql)
no encontró valores nulos ni filas completamente duplicadas.

La vista [stg_transaction_data.sql](../models/staging/stg_transaction_data.sql)
conservó los valores originales:

- Descuentos negativos válidos.
- Ceros en cantidad y venta.
- Signos negativos.
- Filas sin coincidencia con otra tabla, cuando corresponde.

Ejemplo:

```text
RETAIL_DISC = -1.25  → se conserva -1.25
QUANTITY    = 0      → se conserva 0
SALES_VALUE = 0      → se conserva 0
```

Los ceros se conservaron porque pueden representar casos válidos del negocio.
Las combinaciones encontradas fueron revisadas antes de aplicar indicadores:

```text
cantidad = 0 y venta = 0
cantidad = 0 y venta positiva
cantidad positiva y venta = 0
```

# 2. Trabajo realizado en la vista intermedia

La vista [int_sales_promotional_context.sql](../models/intermediate/int_sales_promotional_context.sql)
combina las ventas con información causal, campañas, cupones y redenciones.

## 2.1. Hogares sin campañas activas

Cuando el cruce no encontró campañas activas, se convirtió el valor en cero:

```sql
coalesce(campaigns.active_campaigns_count, 0)
```

Resultado:

```text
Sin campaña encontrada → 0 campañas activas
```

## 2.2. Indicador de campaña activa

El indicador se determinó con base en el número de campañas:

```text
0 campañas → FALSE
1 o más campañas → TRUE
```

## 2.3. Evidencia de promoción

`has_promotion` puede contener tres estados:

```text
TRUE  = existe evidencia positiva de promoción
FALSE = existe evidencia explícita de ausencia
NULL  = no existe suficiente información para determinarlo
```

`NULL` y `FALSE` tienen significados diferentes:

```text
FALSE = se sabe que no existe promoción
NULL  = no se puede determinar si existe promoción
```

## 2.4. Relaciones sin coincidencia

Las relaciones parciales se resolvieron con `LEFT JOIN`, para conservar las
ventas aunque falten coincidencias con otras tablas.

Por ejemplo:

- Una venta puede no tener información causal.
- Un hogar puede no tener perfil demográfico.
- Un producto puede no estar relacionado con una promoción.

En estos casos, se mantiene la venta y queda `NULL` el dato que no pudo
determinarse.

# 3. Trabajo realizado en las dimensiones

Las dimensiones reciben los datos ya preparados por staging y por la vista
intermedia.

## 3.1. `dim_product`

En esta dimensión se conservaron los productos, aunque algunos atributos
descriptivos tengan `NULL`.

```text
product_id = obligatorio
manufacturer = obligatorio según la revisión actual
department = puede ser NULL
brand = puede ser NULL
category = puede ser NULL
subcategory = puede ser NULL
product_size = puede ser NULL
```

No se inventaron datos como departamento, categoría o tamaño.

## 3.2. `dim_household`

La dimensión [dim_household.sql](../models/dimensions/dim_household.sql) reúne
los hogares de ventas, campañas, canjes y demografía.

Se utilizó `UNION` para evitar repetir hogares. Después, `LEFT JOIN` permitió
conservar los hogares que no tienen perfil demográfico:

```text
Hogar sin demografía:

age_group        = NULL
marital_status   = NULL
income_range     = NULL
homeowner_status = NULL
household_size   = NULL
kids_category    = NULL
```

Los hogares sin demografía permanecen en la dimensión y sus ventas permanecen
en `fact_sales`.

Las categorías originales `Unknown` y `None/Unknown` se conservan como texto
cuando sí están registradas.

## 3.3. `dim_time`

Los campos temporales se mantienen como índices del dataset. No se crean fechas
o partes del calendario que no existan en la fuente.

```text
time_id             = obligatorio
dataset_day_number  = obligatorio
dataset_week_number = obligatorio
```

## 3.4. `dim_promotional_context`

Esta dimensión recibe las combinaciones calculadas por la vista intermedia.

```text
promotional_context_id = generado automáticamente
has_promotion = TRUE, FALSE o NULL
display_type = lista JSON o NULL
mailer_type = lista JSON o NULL
household_in_active_campaign = TRUE o FALSE
active_campaigns_count = entero mayor o igual que cero
product_associated_with_coupon = TRUE o FALSE
household_with_redemption_today = TRUE o FALSE
```

Se utilizaron `0` y `FALSE` cuando la ausencia pudo comprobarse. Los `NULL`
se mantuvieron únicamente cuando el dato seguía siendo desconocido.

# 4. Resumen de lo aplicado

| Situación | Resultado aplicado |
|---|---|
| Texto vacío en producto | `NULL` |
| Hogar sin perfil demográfico | `NULL` en atributos demográficos |
| Hogar sin campañas activas | `0` campañas |
| Hogar fuera de campaña | `FALSE` |
| Promoción desconocida | `NULL` |
| Ausencia explícita de promoción | `FALSE` |
| Categoría `Unknown` | Se conserva como texto |
| Categoría `None/Unknown` | Se conserva como texto |
| Descuento negativo válido | Se conserva el signo negativo |
| Cantidad o venta igual a cero | Se conserva el cero |
