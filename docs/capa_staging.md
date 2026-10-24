# Capa staging de Dunnhumby (DUN-12)

## ¿Para qué sirve staging?

`staging` es un esquema de la base `dunnhumby_etl`. Un esquema funciona
como una carpeta que organiza tablas y vistas dentro de una base de datos.

Las ocho tablas originales están en el esquema `public`. En `staging`
se crean ocho vistas para presentar esos datos con nombres y tipos uniformes,
de modo que después sea más fácil trabajar con ellos en dbt.

```text
Tablas originales en public
          ↓
Vistas en staging: nombres en minúsculas y tipos definidos
          ↓
Modelos de dbt: limpieza y transformaciones para el análisis
```

## ¿Por qué usamos vistas?

Una vista es una consulta guardada. No guarda otra copia de los datos:
cuando la consultas, PostgreSQL lee la tabla original.
Si los datos de `public` cambian, esos cambios se reflejan al consultar la vista.

Por ejemplo, para consultar los identificadores de productos desde la vista:

```sql
SELECT product_id
FROM staging.product;
```

Esta consulta usa `staging.product`. Internamente, la vista lee los datos
de `public.product` y presenta la columna original `"PRODUCT_ID"` como
`product_id`. Esa conversión
y ese nombre ya están definidos en `01_crear_staging.sql`; no necesitas
repetirlos al consultar la vista.

Usar minúsculas permite escribir consultas sin comillas dobles. Es una
convención para facilitar el trabajo; dbt no lo exige. La vista no cambia
los nombres ni los valores guardados en las tablas originales.

## ¿Qué vistas se crean?

| Vista en staging | Qué contiene |
| --- | --- |
| `campaign_desc` | Descripción y días de inicio y fin de las campañas. |
| `campaign_table` | Relación entre hogares y campañas. |
| `causal_data` | Información promocional por producto, tienda y semana. |
| `coupon` | Relación entre cupones, productos y campañas. |
| `coupon_redempt` | Registros de canje de cupones por los hogares. |
| `hh_demographic` | Información demográfica disponible de los hogares. |
| `product` | Catálogo y características de los productos. |
| `transaction_data` | Líneas de compra, cantidades, ventas y descuentos. |

Las vistas no crean claves primarias ni foráneas. Por ejemplo, un cupón
puede aparecer asociado a varios productos y una canasta puede tener varias
líneas de compra. Estas relaciones se revisan con las consultas de
`scripts/sql/RevisionCalidad/`.

## Cómo ejecutar los archivos desde SQL en pgAdmin

> **Importante: paso previo a staging.** Antes de ejecutar
> `01_crear_staging.sql` y `02_validar_staging.sql`, debes ejecutar completo
> `scripts/sql/Configuraciones/esquema_roles_permisos.sql` en la base
> `dunnhumby_etl`. Este archivo prepara los esquemas, los roles y sus permisos,
> y usa automáticamente el usuario conectado. Sin esta configuración previa,
> los scripts de staging pueden fallar por falta de roles o permisos.

Antes de empezar, las ocho tablas originales deben estar cargadas en `public`.

Abre **Query Tool** sobre la base **`dunnhumby_etl`** en pgAdmin.
Usa `postgres` u otro usuario administrador con permisos equivalentes para
la configuración inicial. Abre y ejecuta el contenido completo de cada
archivo, en este orden:

| Orden | Archivo | Para qué sirve |
| --- | --- | --- |
| 1 | `scripts/sql/Configuraciones/esquema_roles_permisos.sql` | Prepara los esquemas, los roles y sus permisos. Usa automáticamente el usuario conectado. |
| 2 | `scripts/sql/staging/01_crear_staging.sql` | Crea las ocho vistas y concede acceso de lectura a `rol_staging`. |
| 3 | `scripts/sql/staging/02_validar_staging.sql` | Comprueba que las vistas estén listas para usarse. |

Ejecuta cada archivo completo con el botón de ejecutar o con **F5**,
sin seleccionar solamente una parte del código.

Si ocurre un error y la transacción queda abortada, ejecuta por separado:

```sql
ROLLBACK;
```

Después corrige la causa del error y vuelve a ejecutar el archivo completo.
El `01` crea las vistas sin borrar ni recargar las tablas originales.

## ¿Qué comprueba el archivo 02?

`02_validar_staging.sql` solo lee los datos. Comprueba que:

- La base seleccionada sea `dunnhumby_etl`.
- Existan el esquema `staging` y sus ocho vistas.
- `rol_staging` tenga acceso al esquema y permiso para consultar cada vista.
- Las fuentes no estén vacías.
- Cada vista tenga la misma cantidad de filas que su tabla original.
- Las conversiones funcionen al evaluar todas las columnas de todas las filas.

La última comprobación es necesaria porque crear una vista no garantiza
que todos los valores puedan convertirse al tipo indicado.

Si todo funciona, en **Messages** aparecen ocho mensajes `OK`, uno por
vista, y al final `COMMIT`. También se devuelve una lista de las columnas
y sus tipos. Si una comprobación falla, aparece un error.

La revisión puede tardar porque recorre todos los datos, especialmente
`causal_data`. Ejecútala cuando no se estén recargando las tablas originales.
Que pase esta validación no significa que los datos ya estén limpios:
las revisiones de calidad son una comprobación diferente.

## Consultas para comprobar el consumo y la estructura

En Query Tool de pgAdmin, conectado a `dunnhumby_etl`, ejecutar cada consulta
por separado para observar una muestra de cada fuente:

```sql
SELECT * FROM staging.campaign_desc LIMIT 5;
SELECT * FROM staging.campaign_table LIMIT 5;
SELECT * FROM staging.causal_data LIMIT 5;
SELECT * FROM staging.coupon LIMIT 5;
SELECT * FROM staging.coupon_redempt LIMIT 5;
SELECT * FROM staging.hh_demographic LIMIT 5;
SELECT * FROM staging.product LIMIT 5;
SELECT * FROM staging.transaction_data LIMIT 5;
```

Cada consulta debe devolver cinco filas sin errores con la carga validada.
Para comprobar los nombres de columnas, su orden y los tipos definidos:

```sql
SELECT table_name, column_name, data_type, ordinal_position
FROM information_schema.columns
WHERE table_schema = 'staging'
ORDER BY table_name, ordinal_position;
```

El inventario debe incluir las ocho vistas y sus 46 columnas en total.
Estas consultas adicionales quedan disponibles para comprobación manual;
no se ha compartido evidencia de su ejecución. La integración desde dbt
debe verificarse con la configuración y el usuario correspondientes.
