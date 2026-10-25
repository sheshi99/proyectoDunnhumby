# Capa de staging de Dunnhumby (DUN-12)

La carga actual deja las ocho tablas crudas en `public`, en la base
`dunnhumby_etl`. El script `00_validar_requisitos.sql` crea el esquema `staging`
y los scripts `01_campaign_desc.sql` a `08_transaction_data.sql` crean ocho vistas con columnas explícitas en minúsculas y tipos definidos.
Estas vistas son las relaciones fuente que consumirá dbt. No son ocho
copias físicas: consultan las tablas originales y reflejan sus cambios.
Si se requiere materialización física, debe acordarse esa decisión antes
de considerar este diseño aceptado.

## Relaciones y tipos

| Vista | Grano / significado | Tipos |
| --- | --- | --- |
| campaign_desc | Catálogo de campañas | campaign, start_day, end_day: bigint; description: text |
| campaign_table | Asignación hogar-campaña | household_key, campaign: bigint; description: text |
| causal_data | Exposición promocional producto-tienda-semana | Identificadores y week_no: bigint; display, mailer: text |
| coupon | Asociación cupón-producto-campaña | Todas las columnas: bigint |
| coupon_redempt | Evento de canje | Todas las columnas: bigint |
| hh_demographic | Perfil de hogar | household_key: bigint; atributos: text |
| product | Catálogo de productos | product_id, manufacturer: bigint; atributos: text |
| transaction_data | Línea de compra | Importes y descuentos: numeric; demás columnas: bigint |

Se usa `bigint` para no desbordar canastas y códigos UPC grandes. Los UPC
son numéricos en la carga existente; cualquier cero inicial ya perdido no
se puede recuperar desde PostgreSQL. Los importes se exponen como `numeric`
sin imponer escala ni redondeo adicional; esto no recupera precisión que
la carga original pudiera haber perdido al inferir tipos flotantes.
Los días y semanas siguen siendo índices del dataset; no se inventa una fecha base.
`trans_time` conserva HHMM como entero. `display` y `mailer` conservan sus códigos.

No se eliminan duplicados, espacios, vacíos, etiquetas desconocidas ni nulos.
Se conservan descuentos negativos y hogares sin demografía, según las
revisiones en `scripts/sql/RevisionCalidad/`. La limpieza corresponde a dbt.
Las vistas no imponen claves primarias ni foráneas; los granos documentados
deben comprobarse con las consultas de calidad, no asumirse como restricciones.

## Ejecución en Windows

En pgAdmin, abrir Query Tool en `dunnhumby_etl` y ejecutar el contenido
completo de cada archivo con F5, en este orden:

1. `scripts/sql/Configuraciones/esquema_roles_permisos.sql`.
2. `scripts/sql/staging/00_validar_requisitos.sql`.
3. Los ocho archivos de vistas, en este orden:
   `01_campaign_desc.sql`, `02_campaign_table.sql`, `03_causal_data.sql`,
   `04_coupon.sql`, `05_coupon_redempt.sql`, `06_hh_demographic.sql`,
   `07_product.sql` y `08_transaction_data.sql`.
4. `scripts/sql/staging/09_validar_staging.sql` (validaci?n final, aunque su prefijo sea 02).

No ejecutar solo fragmentos como `FOR ROLE`. Si una ejecución falla dentro
de una transacción, ejecutar `ROLLBACK;` por separado, resolver el error
y repetir el archivo completo. Las tablas originales deben estar cargadas
en `public` antes de crear las vistas.

Primero ejecutar `scripts/sql/Configuraciones/esquema_roles_permisos.sql`
completo en `dunnhumby_etl`, conectado como `postgres` u otro administrador
con permisos equivalentes. Detecta automáticamente al usuario conectado;
no se deben reemplazar nombres. Los esquemas y roles se crean solo si faltan.
La configuración se puede repetir y se ejecuta en una transacción.
Si falla, ejecutar `ROLLBACK;` por separado antes de volver a intentar.
La verificación de membresía debe mostrar ambos roles y la de permisos
debe devolver dos valores `true`. Los permisos futuros corresponden a los
objetos creados por el usuario que ejecuta esta configuración; si dbt usa
otro creador, también se deben configurar sus permisos predeterminados.
El script DUN-12 requiere `rol_staging` y no modifica la configuración
del esquema `data_warehouse`.

Con las ocho tablas ya cargadas, ejecutar cada archivo completo desde Query Tool
de pgAdmin, conectado a `dunnhumby_etl`, siguiendo el orden indicado arriba.

Cada archivo tiene su propia transacción; si falla uno, corregirlo y repetirlo antes de continuar. El conjunto de archivos ya no es atómico. La creación es transaccional por archivo y se puede repetir mientras las columnas de las
vistas mantengan su contrato. No elimina ni recarga tablas originales. La
validación exige ocho vistas, fuentes no vacías, conteos iguales y conversiones
válidas en todas las columnas. Recorre los datos completos y puede tardar,
especialmente en `causal_data`; ejecutarla sin una recarga concurrente.

## Consumo desde dbt

`models/sources/dunnhumby.yml` declara las ocho relaciones. Dentro de un
archivo de modelo `.sql` de dbt, con el proyecto configurado para esta base:

```sql
select product_id, department
from {{ source('dunnhumby', 'product') }}
```

Ese ejemplo requiere dbt; no se ejecuta directamente en pgAdmin.
Para consultar desde pgAdmin usar:

```sql
SELECT product_id, department
FROM staging.product
LIMIT 5;
```

El script de creación concede `USAGE` y `SELECT` a `rol_staging`
explícitamente, independientemente del creador de las vistas. Si dbt usa
un usuario diferente al que ejecutó la configuración, un administrador
debe asignarle `rol_staging`. El archivo de fuentes no configura perfiles
ni credenciales; se incorporará al proyecto dbt cuando este se configure.
La validación comprueba los permisos del rol; la conexión y la membresía
efectiva del usuario de dbt deben comprobarse por separado.

## Antecedente de validación y estado actual

La evidencia siguiente corresponde a la versión anterior de DUN-12.
La versión actual añade permisos explícitos y su comprobación, por lo que
deben ejecutarse nuevamente los scripts de creaci?n y validaci?n y guardar la nueva salida antes
de dar por validada esta versión. No se ha podido ejecutar desde el agente
porque PostgreSQL solicita contraseña.

La captura de pgAdmin compartida durante la revisión muestra la ejecución
exitosa de `09_validar_staging.sql` en `dunnhumby_etl`, con ocho mensajes
`OK`, `COMMIT` y un tiempo de 12 segundos y 115 milisegundos.

| Fuente en staging | Filas confirmadas |
| --- | ---: |
| campaign_desc | 30 |
| campaign_table | 7.208 |
| causal_data | 36.786.524 |
| coupon | 124.548 |
| coupon_redempt | 2.318 |
| hh_demographic | 801 |
| product | 92.353 |
| transaction_data | 2.595.732 |

Estos resultados confirman que las ocho vistas existen, no están vacías,
conservan los conteos de sus tablas en `public` y permiten evaluar las
conversiones de todas sus columnas sin errores. No sustituyen las revisiones
de calidad ni verifican la conexión con el usuario de dbt.

Guardar la captura y la fecha de ejecución como evidencia para DUN-12.
La captura se compartió en el chat; no está incorporada como archivo al repositorio.

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