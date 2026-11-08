# Capa staging

Esta guía cubre los pasos 7 y 8 del [README](../README.md): copiar las tablas
originales a `staging` y crear sobre ellas las vistas limpias con dbt. La
sección 3 explica cómo agregar o modificar una vista.

En `dunnhumby_etl.staging` hay tres tipos de objetos:

| Objeto | Ejemplo | Quién lo crea |
| --- | --- | --- |
| Copia física de una tabla original, con las columnas del CSV | `staging.transaction_data` | Modelos de `models/sincronizacion/` |
| Vista limpia preparada | `staging.stg_transaction_data` | Modelos de `models/staging/` |
| Vista intermedia que prepara una dimensión o los hechos | `staging.int_household`, `staging.int_time`, `staging.int_sales_promotional_context` | Modelos de `models/intermediate/` |

Las copias son la entrada de todo el proceso. El [job automático](job_etl.md)
las sincroniza con `public` en cada ejecución, antes de actualizar el warehouse:
los datos nuevos, modificados o eliminados se cargan en `public` y el job los
lleva a staging.

## 1. Copiar las tablas a staging

Requiere las tablas originales en `public`, los roles configurados
([preparación de las bases](instrucciones_de_carga.md)) y las conexiones de dbt
([inicialización de dbt](inicializacion_dbt.md)).

1. Copiar las ocho tablas con dbt:

   ```powershell
   python -m dotenv -f .env run -- dbt run `
       --profiles-dir . `
       --target dev `
       --select path:models/sincronizacion
   ```

2. Con Query Tool conectado a **`dunnhumby_etl`**, ejecutar completo
   [validar_requisitos.sql](../scripts/sql/staging/validar_requisitos.sql):
   comprueba las copias y concede a `rol_staging` lectura de las fuentes y
   creación en `staging`. Ese rol debe estar asignado al usuario de dbt.

**Resultado esperado:** ocho tablas físicas en `dunnhumby_etl.staging`.

Cómo funciona la copia ([sincronizar_origen.sql](../macros/sincronizar_origen.sql)):

- La primera vez crea cada tabla con todas las filas de `public`. Conserva
  nombres, tipos y registros, pero no índices ni restricciones. `public` queda
  intacto.
- Las siguientes veces solo aplica las diferencias: inserta las filas nuevas y
  borra las que ya no están en `public`. Una fila modificada se borra en su
  versión anterior y se inserta en la nueva. El log indica cuántas filas se
  borraron e insertaron en cada tabla.
- Las tablas no tienen clave única y hay filas repetidas legítimas, por eso se
  compara cuántas veces aparece cada fila: si `public` tiene una fila tres veces,
  staging también.
- Cada tabla se actualiza en una sola transacción. `causal_data` es grande: su
  comparación tarda unos 3 minutos.
- Si las columnas de una tabla de `public` cambian, la ejecución se detiene sin
  modificar la copia.

## 2. Crear las vistas limpias

1. Crear las ocho vistas `stg_` y las tres vistas intermedias `int_`:

   ```powershell
   python -m dotenv -f .env run -- dbt run `
       --profiles-dir . `
       --target dev `
       --select path:models/staging path:models/intermediate
   ```

2. Ejecutar las pruebas de las vistas:

   ```powershell
   python -m dotenv -f .env run -- dbt test `
       --profiles-dir . `
       --target dev `
       --select path:models/staging path:models/intermediate
   ```

3. Como comprobación adicional, ejecutar
   [validar_staging.sql](../scripts/sql/staging/validar_staging.sql) en
   Query Tool conectado a `dunnhumby_etl`. Compara las vistas de transacciones y
   datos causales con sus copias y revisa las conversiones de tipos.

**Resultado esperado:** ocho vistas `stg_` y las tres vistas `int_` en
`dunnhumby_etl.staging`, con las pruebas en `PASS`.

Las vistas solo renombran columnas, convierten tipos y normalizan textos. Los
descuentos conservan sus signos, no se eliminan filas ni ceros, y los días y
semanas se conservan como índices del dataset. `stg_transaction_data` agrega
`transaction_date`, calculada desde la fecha base supuesta `2004-01-01`.
Los textos vacíos de producto se reemplazan por `'not available'`; ver
[tratamiento de nulos](tratamiento_nulos.md).

Para agregar o modificar una vista, ver la
[sección 3](#3-agregar-o-modificar-una-vista).

Siguiente paso: [crear el modelo estrella](guia_modelo_estrella_dbt.md#7-ejecución).

## 3. Agregar o modificar una vista

Esta sección es una guía sencilla para agregar una tabla al proceso de limpieza
del proyecto. La idea principal es:

```text
staging.tabla_original  →  dbt transforma los datos  →  staging.stg_tabla
     entrada                         modelo SQL             salida
```

En `dunnhumby_etl.public` se conservan las tablas originales cargadas desde CSV.
Sus copias de trabajo están en `dunnhumby_etl.staging`; en ese mismo esquema dbt
crea las vistas limpias con prefijo `stg_`. Las dimensiones y hechos se construyen
posteriormente en la segunda base, `Data_warehouse`, según el [README](../README.md).

### Paso 1: revisa la calidad de la tabla

Busca la revisión correspondiente en `scripts/sql/RevisionCalidad/` y léela
antes de escribir SQL. Anota:

- cuáles columnas tiene la tabla;
- qué problemas encontró la revisión;
- qué acciones propone su conclusión.

Una consulta de calidad sirve para encontrar problemas; por sí sola no indica
que haya que borrar filas. No uses `WHERE` para quitar registros ni `DISTINCT`
para eliminar duplicados, a menos que la revisión y el equipo hayan confirmado
que se deben descartar. Si el archivo no muestra el resultado de una consulta,
ejecútala en pgAdmin antes de decidir.

### Paso 2: declara la tabla de entrada

Abre `models/sources/dunnhumby.yml`. Busca la fuente `dunnhumby`, que apunta a
las tablas originales de `public`, y agrega el nombre de la tabla bajo `tables:`.
Por ejemplo:

```yaml
- name: dunnhumby
  schema: public
  tables:
  - name: campaign_desc
  - name: coupon_redempt
  - name: nombre_de_otra_tabla
```

`nombre_de_otra_tabla` es un ejemplo: reemplázalo por el nombre real.

Esta declaración no crea tablas. Le indica a dbt dónde encontrar las tablas
originales. Para copiarla a staging, crea `models/sincronizacion/nombre_de_otra_tabla.sql`
igual que los demás archivos de esa carpeta:

```sql
select * from {{ source('dunnhumby', 'nombre_de_otra_tabla') }}
```

### Paso 3: crea el modelo que limpia los datos

Dentro de `models/staging/`, crea un archivo SQL con el prefijo `stg_`. El
nombre del archivo se convertirá en el nombre del modelo. Por ejemplo:
`models/staging/stg_nombre_de_otra_tabla.sql`.

Usa esta estructura como guía y reemplaza las columnas por las de tu tabla:

```sql
{{ config(
    materialized='view',
    grants={'select': ['rol_staging']}
) }}

select
    "COLUMNA_ID" as id,
    trim("DESCRIPCION") as descripcion
from {{ ref('nombre_de_otra_tabla') }}
```

Aplica solo las transformaciones justificadas por la revisión: por ejemplo,
renombrar columnas o normalizar texto si hace falta. En PostgreSQL, las
columnas originales que están en mayúsculas deben escribirse con comillas
dobles, como `"PRODUCT_ID"`. Confirma los nombres reales en la tabla o en su
CSV.

No pongas comentarios `--` dentro de `{{ config(...) }}`. Ponlos debajo del
bloque de configuración.

#### Ejemplos de este proyecto

- `stg_campaign_descriptions.sql` prepara las columnas de campaña y recorta
  espacios de la descripción. La revisión reporta 30 campañas sin problemas
  de calidad, así que no hace falta filtrar filas.
- `stg_coupon_redemptions.sql` estandariza los nombres de columnas y conserva
  las redenciones. No elimina hogares sin demografía. No quites duplicados
  hasta revisar el resultado de la consulta correspondiente.

### Paso 4: documenta el modelo (opcional)

`models/staging/staging.yml` describe los modelos y sus columnas. Esta
documentación no transforma datos y no es necesaria para ejecutar `dbt run`.
Si agregas una descripción, el nombre debe coincidir con el archivo SQL sin
`.sql`, y las columnas deben coincidir con los alias del `SELECT`.

Agrega el modelo dentro de la lista `models:` que ya existe. No crees otro
bloque `models:` en el mismo archivo.

### Paso 5: verifica la conexión y la configuración

Abre PowerShell en la carpeta del proyecto. Ejecuta:

```powershell
python -m dotenv -f .env run -- dbt debug --profiles-dir . --target dev
```

Continúa cuando el resultado muestre `All checks passed!`. Este comando
comprueba que dbt puede conectarse a PostgreSQL.

### Paso 6: revisa que dbt entienda el proyecto

Ejecuta:

```powershell
python -m dotenv -f .env run -- dbt parse --profiles-dir .
```

`dbt parse` comprueba la sintaxis y que las fuentes mencionadas por los
modelos estén declaradas. No crea vistas ni cambia datos.

Si aparece `depends on a source named ... which was not found`, revisa que el
nombre de la fuente y el de la tabla coincidan entre el SQL y
`dunnhumby.yml`.

### Paso 7: ejecuta solo tu modelo

El nombre para `--select` viene del archivo SQL, sin `.sql`. Si el archivo se
llama `stg_nombre_de_otra_tabla.sql`, ejecuta:

```powershell
python -m dotenv -f .env run -- dbt run --target dev --select stg_nombre_de_otra_tabla --profiles-dir .
```

Para ejecutar todos los modelos SQL que estén dentro de `models/staging/`, usa:

```powershell
python -m dotenv -f .env run -- dbt run --target dev --select path:models/staging --profiles-dir .
```

Este selector incluye los modelos de esa carpeta, incluidos los que se agreguen
más adelante. `dbt run` no ejecuta las pruebas declaradas en YAML; para correrlas,
usa `dbt test`.

En este proyecto, el target `dev` configura el esquema de salida como `staging`,
y los modelos de esa carpeta se materializan como vistas. Por eso dbt crea las
salidas en `staging`. `dbt run` sin `--select` intenta ejecutar todos los
modelos del proyecto.

### Paso 8: revisa el resultado

En pgAdmin, consulta la vista nueva. Compara la cantidad de filas con la tabla
original si el modelo no elimina registros. Por ejemplo:

```sql
SELECT COUNT(*) FROM staging.campaign_desc;
SELECT COUNT(*) FROM staging.stg_campaign_descriptions;

SELECT COUNT(*) FROM staging.coupon_redempt;
SELECT COUNT(*) FROM staging.stg_coupon_redemptions;
```

También revisa una muestra de filas y confirma que los nombres y valores sean
los esperados. Si agregaste un `JOIN`, verifica que no haya multiplicado las
filas.

### Configuración y contraseñas

Cada integrante configura sus credenciales localmente en `.env` y
`profiles.yml`. No suban ni compartan esos archivos. El usuario de dbt necesita
permiso para leer las tablas de entrada y crear vistas en el esquema de salida.
