# Tratamiento de datos nulos y desconocidos

## Procedimiento realizado

Para realizar el tratamiento de valores faltantes, primero revisamos los datos
fuente por medio de las [consultas de calidad](../scripts/sql/RevisionCalidad/).
Los datos originales no tienen valores `NULL`. Los datos faltantes aparecen en
dos casos:

- **Textos vacíos en la fuente:** campos de producto que solo contienen espacios.
- **Cruces sin coincidencia:** por ejemplo, un hogar que compra pero no tiene
  perfil demográfico, o una venta sin datos causales de promoción.

Con estos resultados aplicamos las recomendaciones de Kimball:

1. **Los atributos de las dimensiones no quedan en `NULL`.** Se reemplazan por
   un texto que explica por qué falta el dato.
2. **Los indicadores verdadero/falso se guardan como texto**, para que se
   entiendan en los reportes y las tablas dinámicas.
3. **Las claves foráneas de la tabla de hechos nunca son `NULL`.**
4. **Las medidas de la tabla de hechos no se modifican.**

Los textos van en inglés, igual que las columnas y los valores de la fuente. No
se usa `Unknown` porque la fuente ya lo trae con otro significado.

## Justificación de las reglas

1. **No eliminar filas por datos incompletos.** La pérdida de un atributo
   descriptivo no convierte en inválida una transacción. Por ello, los hogares
   sin demografía y las ventas sin coincidencia promocional se mantienen.

2. **Explicar el motivo del dato faltante.** Un `NULL` aparece como "(en
   blanco)" en una tabla dinámica y no dice por qué falta. Un texto como
   `'No demographic profile'` forma un grupo propio que se puede contar y filtrar.

3. **Distinguir ausencia desconocida de ausencia comprobada.** `'No promotion'`
   indica que se sabe que no hubo promoción; `'Undetermined'` indica que no se
   puede saber.

4. **Conservar la trazabilidad de la fuente.** Las categorías originales, como
   `Unknown` o `None/Unknown`, y los signos negativos no se modifican sin una
   regla de negocio que lo justifique.

5. **Resolver cada dato en la capa correspondiente.** La limpieza de la fuente
   se hace en las vistas `stg_`, los cruces entre tablas en las vistas
   intermedias `int_`, y las dimensiones solo insertan valores ya preparados.

## Resumen de decisiones por capa

| Capa | Qué se hizo | Justificación |
|---|---|---|
| Staging (`stg_`) | Los textos vacíos de producto se reemplazaron por `'not available'`. | Normaliza los faltantes de la fuente sin eliminar registros. |
| Vistas intermedias (`int_`) | Los cruces sin coincidencia y los indicadores se convirtieron en textos descriptivos. | Los faltantes aparecen al unir tablas; se resuelven donde se hace la unión. |
| Dimensiones | Insertan los valores preparados; sus atributos son obligatorios. | Las dimensiones no vuelven a aplicar reglas de negocio. |
| Data Warehouse | Esquema estrella con IDs propios y llaves foráneas obligatorias. | Cada venta queda relacionada con todas sus dimensiones. |

# 1. Trabajo realizado en las vistas de staging

Las vistas de staging tienen como función limpiar los datos y dejarlos
preparados antes de crear las dimensiones.

## 1.1. Productos

La revisión de calidad encontró campos descriptivos que solo contenían espacios:
15 departamentos, 15 categorías, 15 subcategorías y 30 607 tamaños. Para
corregirlos se utilizó la vista
[stg_product.sql](../models/staging/stg_product.sql).

Después de eliminar los espacios externos, las cadenas vacías se reemplazan por
`'not available'`:

```sql
coalesce(nullif(lower(btrim("DEPARTMENT")), ''), 'not available')
```

La misma regla se aplica a marca, categoría, subcategoría y tamaño. Va en
minúscula porque la vista convierte todos los textos a minúscula.

Ejemplo:

```text
"   "       → "not available"
"GROCERY"   → "grocery"
```

Las etiquetas `NO COMMODITY DESCRIPTION` y `NO SUBCOMMODITY DESCRIPTION`
también se conservaron, porque son textos registrados por la fuente.

## 1.2. Demografía

La vista [stg_hh_demographic.sql](../models/staging/stg_hh_demographic.sql)
conservó las categorías originales `Unknown` y `None/Unknown`.

El estado civil (`MARITAL_STATUS_CODE`) llega como letra y se traduce después,
en `int_household` (ver la sección 2.1).

Estas categorías son diferentes de un hogar sin perfil:

```text
Unknown                = categoría registrada por la fuente
None/Unknown           = categoría registrada por la fuente
No demographic profile = el hogar no aparece en hh_demographic
```

## 1.3. Transacciones

La revisión de [transaction_data.sql](../scripts/sql/RevisionCalidad/transaction_data.sql)
no encontró valores nulos ni filas completamente duplicadas.

La vista [stg_transaction_data.sql](../models/staging/stg_transaction_data.sql)
conservó los valores originales:

- Descuentos negativos válidos.
- Ceros en cantidad y venta.
- Signos negativos.

Además, agrega `transaction_date`, una fecha calculada a partir de la fecha
base `2004-01-01` más los días del dataset (`DAY - 1`). Dunnhumby no publica
fechas reales, por lo que esta fecha es un supuesto del proyecto.

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

## 1.4. Campañas, cupones y redenciones

Las vistas [stg_campaign_descriptions.sql](../models/staging/stg_campaign_descriptions.sql),
[stg_campaign_table.sql](../models/staging/stg_campaign_table.sql),
[stg_coupon.sql](../models/staging/stg_coupon.sql) y
[stg_coupon_redemptions.sql](../models/staging/stg_coupon_redemptions.sql)
prepararon estas tablas de la siguiente manera:

- Se convirtieron los identificadores al tipo requerido.
- Se estandarizaron los nombres de las columnas.
- Se conservaron todas las asignaciones y redenciones.

En `stg_campaign_descriptions` se aplica `trim` a `DESCRIPTION` para eliminar los
espacios externos del tipo de campaña.

```sql
trim("DESCRIPTION") as campaign_type
```

En `stg_coupon` se utiliza `select distinct` para eliminar las 5 164 filas
completamente duplicadas y mantener una sola asociación entre cupón, producto y
campaña.

Estas tablas no tienen valores nulos ni vacíos, por lo que no requirieron
sustitución.

## 1.5. Datos causales

La vista [stg_causal_data.sql](../models/staging/stg_causal_data.sql) conserva
los códigos originales `display` y `mailer`.

Las revisiones de calidad encontraron que estas columnas no contienen valores
vacíos ni nulos. Por esta razón, se preservan los códigos existentes y la vista
intermedia interpreta su significado promocional.

Además, la vista agrega `display_description` y `mailer_description`, con la
descripción de cada código según la guía de dunnhumby (ver la sección 6). Un
código que no estuviera en esas tablas quedaría como `'Unknown code X'`, nunca
como `NULL`.

# 2. Trabajo realizado en las vistas intermedias

## 2.1. Hogares: `int_household`

La vista [int_household.sql](../models/intermediate/int_household.sql) reúne los
hogares de ventas, campañas, canjes y demografía con `UNION`, que deja cada
hogar una sola vez. Después agrega su perfil con `LEFT JOIN`.

La revisión de calidad encontró 1 699 hogares con compras que no aparecen en
`hh_demographic`. A estos hogares les faltan los siete atributos a la vez, por
lo que se usa un solo texto:

```text
age_group             = 'No demographic profile'
marital_status        = 'No demographic profile'
income_range          = 'No demographic profile'
homeowner_status      = 'No demographic profile'
household_composition = 'No demographic profile'
household_size        = 'No demographic profile'
kids_category         = 'No demographic profile'
```

El estado civil se traduce según la guía de dunnhumby: `A` → `'Married'`,
`B` → `'Single'` y `U` → `'Unknown'`. Este `'Unknown'` es el valor que registra
la fuente, no un dato faltante.

Los hogares sin perfil permanecen en la dimensión y sus ventas permanecen en
`fact_sales`.

## 2.2. Contexto promocional: `int_sales_promotional_context`

La vista [int_sales_promotional_context.sql](../models/intermediate/int_sales_promotional_context.sql)
combina las ventas con información causal, campañas, cupones y redenciones. Las
relaciones se resuelven con `LEFT JOIN`, para conservar las ventas aunque falten
coincidencias con otras tablas.

**Evidencia de promoción.** `has_promotion` tiene tres estados:

```text
'Promotion'    = existe evidencia positiva de promoción
'No promotion' = existe evidencia explícita de ausencia
'Undetermined' = no existe suficiente información para determinarlo
```

En los datos actuales ninguna venta queda como `'No promotion'`, porque los
datos causales no registran una ausencia explícita (display y mailer en `0`)
para ninguna combinación de producto, tienda y semana.

**Ventas sin datos causales.** Cuando una venta no tiene coincidencia en los
datos causales, `display_type` y `mailer_type` quedan como `'No causal data'`.

**Campañas activas.** Cuando el cruce no encuentra campañas activas, el conteo
queda en cero y el indicador se define con base en ese conteo:

```text
0 campañas       → 'Not in campaign'
1 o más campañas → 'In campaign'
```

**Cupones y canjes:**

```text
Hogar en campaña TypeB/TypeC vigente con cupón del producto → 'Coupon received'
Otro cupón vigente para el producto                         → 'Coupon available'
Sin cupón vigente                                           → 'No coupon'
Hogar con canje el mismo día          → 'Redeemed', si no 'Not redeemed'
```

## 2.3. Tiempo: `int_time`

La vista [int_time.sql](../models/intermediate/int_time.sql) calcula los
atributos de calendario de cada día a partir de `transaction_date`. Todos los
días del dataset tienen ventas, fecha y semana, por lo que esta vista no
genera nulos.

# 3. Trabajo realizado en las dimensiones

Las dimensiones solo insertan los datos ya preparados por las vistas. Cada una
tiene un ID propio generado por el warehouse y conserva el código original de
Dunnhumby.

## 3.1. `dim_product`

```text
dim_product_id = obligatorio (ID propio)
product_id     = obligatorio (código original)
manufacturer   = obligatorio
department, brand, category, subcategory, product_size
               = obligatorios; 'not available' si la fuente los trae vacíos
```

## 3.2. `dim_household`

```text
dim_household_id = obligatorio (ID propio)
household_id     = obligatorio (código original)
atributos        = obligatorios; 'No demographic profile' sin perfil
```

Las categorías originales `Unknown` y `None/Unknown` se conservan como texto
cuando sí están registradas. `marital_status` guarda la descripción
(`Married`, `Single` o `Unknown`), no la letra.

## 3.3. `dim_time`

Todas las columnas son obligatorias, igual que en la dimensión de tiempo del
curso.

```text
dim_time_id         = obligatorio (fecha como AAAAMMDD)
calendar_date       = obligatorio y único
dataset_day_number  = obligatorio y único (DAY original)
dataset_week_number = obligatorio (WEEK_NO original)
```

## 3.4. `dim_promotional_context`

```text
dim_promotional_context_id      = generado automáticamente
has_promotion                   = 'Promotion', 'No promotion' o 'Undetermined'
display_type                    = descripción (por ejemplo, 'In-aisle') o 'No causal data'
mailer_type                     = descripción (por ejemplo, 'Front page feature') o 'No causal data'
household_in_active_campaign    = 'In campaign' o 'Not in campaign'
active_campaigns_count          = entero mayor o igual que cero
product_associated_with_coupon  = 'Coupon received', 'Coupon available' o 'No coupon'
household_with_redemption_today = 'Redeemed' o 'Not redeemed'
```

# 4. Resumen de lo aplicado

| Situación | Resultado aplicado |
|---|---|
| Texto vacío en producto | `'not available'` |
| Hogar sin perfil demográfico | `'No demographic profile'` en los siete atributos |
| Hogar sin campañas activas | `0` campañas y `'Not in campaign'` |
| Venta sin datos causales | `'Undetermined'` y `'No causal data'` |
| Ausencia explícita de promoción | `'No promotion'` |
| Categoría `Unknown` o `None/Unknown` | Se conserva como texto |
| Descuento negativo válido | Se conserva el signo negativo |
| Cantidad o venta igual a cero | Se conserva el cero |
| Llaves de `fact_sales` | Obligatorias; la carga falla si una venta no encuentra su dimensión |

# 5. Verificación

En Query Tool conectado a `Data_warehouse`, los tres conteos deben ser `0`:

```sql
SELECT count(*) FROM dim_household WHERE age_group IS NULL;
SELECT count(*) FROM dim_product WHERE department IS NULL;
SELECT count(*) FROM dim_promotional_context WHERE display_type IS NULL;
```

# 6. Códigos de display y mailer

`display_type` y `mailer_type` ya no guardan los códigos de Dunnhumby, sino su
descripción según la guía oficial del dataset (por ejemplo, `["7"]` ahora es
`'In-aisle'`). El detalle está en
[actualizacion_proyecto.md](actualizacion_proyecto.md#2-códigos-de-display-y-mailer).
