# Guía sencilla para limpiar tablas con dbt

Esta guía es para agregar una tabla al proceso de limpieza del proyecto. La
idea principal es:

```text
staging.tabla_original  →  dbt transforma los datos  →  staging.stg_tabla
     entrada                         modelo SQL             salida
```

`staging` es donde están las tablas originales cargadas desde los CSV.
`staging` es donde dbt crea las vistas limpias. Son esquemas distintos y cada
uno cumple una función distinta.

## Paso 1: revisa la calidad de la tabla

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

## Paso 2: declara la tabla de entrada

Abre `models/sources/dunnhumby.yml`. Busca la fuente `dunnhumby_raw`, que en
este proyecto apunta a `public`, y agrega el nombre de la tabla bajo `tables:`.
Por ejemplo:

```yaml
- name: dunnhumby_raw
  schema: staging
  tables:
  - name: campaign_desc
  - name: coupon_redempt
  - name: nombre_de_otra_tabla
```

`nombre_de_otra_tabla` es un ejemplo: reemplázalo por el nombre real. Inclúyelo
en `dunnhumby_raw` solo si la tabla está en `public`. Todas las tablas listadas
bajo una fuente comparten el mismo esquema.

Esta declaración no crea tablas. Le indica a dbt dónde encontrar las tablas
que ya existen. Si una tabla está en otro esquema, declárala en otra fuente y
especifica ese esquema.

## Paso 3: crea el modelo que limpia los datos

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
from {{ source('dunnhumby_raw', 'nombre_de_otra_tabla') }}
```

Aplica solo las transformaciones justificadas por la revisión: por ejemplo,
renombrar columnas o normalizar texto si hace falta. En PostgreSQL, las
columnas originales que están en mayúsculas deben escribirse con comillas
dobles, como `"PRODUCT_ID"`. Confirma los nombres reales en la tabla o en su
CSV.

No pongas comentarios `--` dentro de `{{ config(...) }}`. Ponlos debajo del
bloque de configuración.

### Ejemplos de este proyecto

- `stg_campaign_descriptions.sql` prepara las columnas de campaña y recorta
  espacios de la descripción. La revisión reporta 30 campañas sin problemas
  de calidad, así que no hace falta filtrar filas.
- `stg_coupon_redemptions.sql` estandariza los nombres de columnas y conserva
  las redenciones. No elimina hogares sin demografía. No quites duplicados
  hasta revisar el resultado de la consulta correspondiente.

## Paso 4: documenta el modelo (opcional)

`models/staging/staging.yml` describe los modelos y sus columnas. Esta
documentación no transforma datos y no es necesaria para ejecutar `dbt run`.
Si agregas una descripción, el nombre debe coincidir con el archivo SQL sin
`.sql`, y las columnas deben coincidir con los alias del `SELECT`.

Agrega el modelo dentro de la lista `models:` que ya existe. No crees otro
bloque `models:` en el mismo archivo.

## Paso 5: verifica la conexión y la configuración

Abre PowerShell en la carpeta del proyecto. Ejecuta:

```powershell
python -m dotenv -f .env run -- dbt debug --profiles-dir .
```

Continúa cuando el resultado muestre `All checks passed!`. Este comando
comprueba que dbt puede conectarse a PostgreSQL.

## Paso 6: revisa que dbt entienda el proyecto

Ejecuta:

```powershell
python -m dotenv -f .env run -- dbt parse --profiles-dir .
```

`dbt parse` comprueba la sintaxis y que las fuentes mencionadas por los
modelos estén declaradas. No crea vistas ni cambia datos.

Si aparece `depends on a source named ... which was not found`, revisa que el
nombre de la fuente y el de la tabla coincidan entre el SQL y
`dunnhumby.yml`.

## Paso 7: ejecuta solo tu modelo

El nombre para `--select` viene del archivo SQL, sin `.sql`. Si el archivo se
llama `stg_nombre_de_otra_tabla.sql`, ejecuta:

```powershell
python -m dotenv -f .env run -- dbt run --select stg_nombre_de_otra_tabla --profiles-dir .
```

Para ejecutar todos los modelos SQL que estén dentro de `models/staging/`, usa:

```powershell
python -m dotenv -f .env run -- dbt run --select path:models/staging --profiles-dir .
```

Este selector incluye los modelos de esa carpeta, incluidos los que se agreguen
más adelante. `dbt run` no ejecuta las pruebas declaradas en YAML; para correrlas,
usa `dbt test`.

En este proyecto, `.env` configura el esquema de salida como `staging`, y
`dbt_project.yml` configura los modelos como vistas. Por eso dbt crea las
salidas en `staging`. `dbt run` sin `--select` intenta ejecutar todos los
modelos del proyecto.

## Paso 8: revisa el resultado

En pgAdmin, consulta la vista nueva. Compara la cantidad de filas con la tabla
original si el modelo no elimina registros. Por ejemplo:

```sql
SELECT COUNT(*) FROM public.campaign_desc;
SELECT COUNT(*) FROM staging.stg_campaign_descriptions;

SELECT COUNT(*) FROM public.coupon_redempt;
SELECT COUNT(*) FROM staging.stg_coupon_redemptions;
```

También revisa una muestra de filas y confirma que los nombres y valores sean
los esperados. Si agregaste un `JOIN`, verifica que no haya multiplicado las
filas.

## Configuración y contraseñas

Cada integrante configura sus credenciales localmente en `.env` y
`profiles.yml`. No suban ni compartan esos archivos. El usuario de dbt necesita
permiso para leer las tablas de entrada y crear vistas en el esquema de salida.
