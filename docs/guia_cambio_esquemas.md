# Guía del equipo: carga con dbt y esquemas `raw` y `dw`

Esta guía explica los dos cambios recientes del proyecto, qué debe hacer cada integrante en su equipo y cómo comprobar que todo funciona.

## 1. Qué cambió

| Cambio | Quién | Qué hace |
| --- | --- | --- |
| Carga de los CSV con dbt | Walbyn | La macro `cargar_csv` carga los ocho CSV de `database/` con `COPY` de PostgreSQL. Ya no se usa pandas. |
| Esquemas nuevos | Seidy | `public` deja de usarse para datos. Los CSV originales van a `raw` y el modelo estrella a `dw`. |

| Base de datos | Antes | Ahora | Contenido |
| --- | --- | --- | --- |
| `dunnhumby_etl` | `public` | **`raw`** | Ocho tablas originales cargadas desde los CSV. |
| `dunnhumby_etl` | `staging` | `staging` (igual) | Ocho copias de trabajo y 11 vistas (`stg_` e `int_`). |
| `Data_warehouse` | `public` | **`dw`** | Cuatro dimensiones y `fact_sales`. |

```text
CSV → raw → copias en staging → vistas stg_/int_ → dw
```

El resultado final no cambia: `fact_sales` sigue siendo una fila por cada línea de compra original.

## 2. Qué debe hacer cada integrante

Todos los integrantes ya tienen datos cargados en `public`, así que el camino es:

| Paso | Qué se hace |
| --- | --- |
| 3 y 4 | Actualizar el proyecto y `profiles.yml`. |
| 5 | Migrar las tablas de `public` a `raw` y `dw`. |
| 7 | Construir los modelos y comprobar los resultados. |
| 8 | Probar el job de pgAgent (solo quien lo use). |
| 9 | Probar la carga con dbt de Walbyn (opcional). |

## 3. Preparación (todos)

- Si está activo el job de pgAgent, no ejecutar dbt mientras corre. Se puede esperar a que termine o desactivarlo.
- Cerrar Excel y las pestañas de pgAdmin que usen `Data_warehouse`.
- Conservar `venv`, `.env`, `profiles.yml` y los ocho CSV de `database/`.
- Actualizar el proyecto y activar el entorno, desde la raíz:

```powershell
git pull
.\venv\Scripts\Activate.ps1
```

Si los cambios todavía están en la rama `seidy`, usar `git fetch` y `git checkout seidy`.

## 4. Actualizar `profiles.yml` (todos)

Este archivo es local y no se sube a Git. En el bloque `warehouse`, cambiar el esquema:

```yaml
    warehouse:
      ...
      dbname: Data_warehouse
      schema: dw
```

El bloque `dev` no cambia. Para guardar el cambio, usar el editor de VS Code. Evitar comandos como `sed -i`, que recrean el archivo (ver el paso 8).

## 5. Ya tengo datos en `public`: migrar las tablas

La migración mueve las tablas sin copiar filas. Se conservan los datos, los IDs y las claves foráneas.

1. En pgAdmin, abrir Query Tool conectado a **`dunnhumby_etl`** y ejecutar el **bloque 1** de [migrar_esquemas.sql](../scripts/sql/Configuraciones/migrar_esquemas.sql).
2. Abrir Query Tool conectado a **`Data_warehouse`** y ejecutar el **bloque 2** del mismo archivo.
3. Ejecutar de nuevo los scripts de roles y permisos, cada uno en su base:
   - [staging_roles_permisos.sql](../scripts/sql/Configuraciones/staging_roles_permisos.sql) en `dunnhumby_etl`.
   - [warehouse_roles_permisos.sql](../scripts/sql/Configuraciones/warehouse_roles_permisos.sql) en `Data_warehouse`.

Cada script verifica la base en la que está y se detiene con un mensaje si es la equivocada. Los avisos `NOTICE ... ya existe` son normales.

Seguir con el paso 7.

## 6. Instalación desde cero (no aplica al equipo hoy)

Este caso no se necesita si las bases ya tienen datos. Si algún día se instala en un equipo nuevo, primero se crean las bases y la conexión `dblink` según [instrucciones_de_carga.md](instrucciones_de_carga.md), se ejecutan los dos scripts de roles y permisos del paso 5.3 (crean `raw` y `dw`) y se carga con [carga_csv_dbt.md](carga_csv_dbt.md).

## 7. Construir los modelos

Los datos ya están en `raw`, así que **no** se usa `cargar_csv`. Ejecutar en orden, y el segundo solo si el primero termina sin errores:

```powershell
python -m dotenv -f .env run -- dbt build --profiles-dir . --target dev --select path:models/sincronizacion path:models/staging path:models/intermediate

python -m dotenv -f .env run -- dbt build --profiles-dir . --target warehouse --select path:models/dimensions path:models/facts
```

El build del warehouse tarda cerca de 8 minutos por `fact_sales`.

### Cómo comprobar que va bien

**a) Los builds.** Cada uno debe terminar con `Completed successfully` y `ERROR=0`. En la prueba de Seidy:

| Build | Pruebas | Errores |
| --- | ---: | ---: |
| `dev` | 44 | 0 |
| `warehouse` | 28 | 0 |

**b) Dónde está cada tabla.** En `dunnhumby_etl`:

```sql
SELECT table_schema, count(*) AS objetos
FROM information_schema.tables
WHERE table_schema IN ('public', 'raw', 'staging')
GROUP BY table_schema ORDER BY table_schema;
```

En `Data_warehouse`:

```sql
SELECT table_schema, count(*) AS objetos
FROM information_schema.tables
WHERE table_schema IN ('public', 'dw')
GROUP BY table_schema ORDER BY table_schema;
```

| Base | Esquema | Objetos esperados |
| --- | --- | ---: |
| `dunnhumby_etl` | `raw` | 8 |
| `dunnhumby_etl` | `staging` | 19 (8 copias y 11 vistas) |
| `dunnhumby_etl` | `public` | 0 (no aparece) |
| `Data_warehouse` | `dw` | 5 (4 dimensiones y `fact_sales`) |
| `Data_warehouse` | `public` | 0 (no aparece) |

**c) Conteos de registros.**

```sql
-- conectado a dunnhumby_etl
SELECT count(*) FROM raw.transaction_data;
SELECT count(*) FROM raw.causal_data;

-- conectado a Data_warehouse
SELECT count(*) FROM dw.fact_sales;
```

| Comprobación | Registros esperados |
| --- | ---: |
| `raw.transaction_data` | 2 595 732 |
| `raw.causal_data` | 36 786 524 |
| `dw.fact_sales` | 2 595 732 |

Los conteos son una comprobación inicial; no demuestran por sí solos que cada valor sea igual.

**d) Limpieza de dimensiones** (el último paso del job). Debe terminar sin mensajes de error:

```powershell
python -m dotenv -f .env run -- dbt run-operation limpiar_dimensiones --profiles-dir . --target warehouse
```

## 8. Job de pgAgent (solo quien lo use)

El job `Dunnhumby_ETL_madrugada` ejecuta esos mismos pasos todos los días a las 2:00 a. m. Para que corra solo, deben estar activados **el job y su horario "Diario 02:00"** (sin cruz roja en pgAdmin), el servicio de pgAgent en ejecución y el equipo encendido a esa hora. El horario usa la zona horaria del servidor de PostgreSQL.

### Permisos del servicio

El job se ejecuta con la cuenta de Windows `SERVICIO LOCAL`, no con el usuario de cada integrante. Necesita permiso de lectura sobre tres archivos de la raíz. Si falta uno, el job falla a los 5 segundos con `Permission denied`.

```powershell
icacls .env /grant "*S-1-5-19:(RX)"
icacls profiles.yml /grant "*S-1-5-19:(RX)"
icacls dbt_project.yml /grant "*S-1-5-19:(RX)"
```

Se pueden ejecutar varias veces sin problema. Para ver si un archivo lo tiene, `icacls profiles.yml` debe mostrar una línea con `SERVICIO LOCAL:(RX)`.

**Cuándo se pierde ese permiso:** cuando un comando recrea el archivo, por ejemplo `sed -i`, `git restore` o ciertos `git pull` que lo modifican. Si el job falla con `Permission denied`, repetir el `icacls` del archivo que menciona el log.

### Cómo probar el job

1. En pgAdmin, clic derecho sobre el job → **Run now**. Debe aparecer el mensaje verde `Updated the next runtime to now`.
2. En la base **`postgres`** (no en `dunnhumby_etl`), ejecutar:

```sql
SELECT jlgstatus, jlgstart, jlgduration
FROM pgagent.pga_joblog
ORDER BY jlgid DESC LIMIT 3;
```

   El estado `r` es corriendo, `s` terminó bien y `f` falló. La duración (`jlgduration`) queda vacía mientras corre.

3. Al terminar, `logs/jobs/ultima_ejecucion.json` debe decir `"estado": "CORRECTO"`, y el log nuevo está en `logs/jobs/`.

En la prueba de Seidy, el job tardó unos 11 minutos y terminó en `s`, con los mismos 44 y 28 resultados correctos del paso 7.

## 9. Probar la carga con dbt de Walbyn (opcional)

Sirve para comprobar que la carga desde los CSV funciona en cada equipo. **Borra las ocho tablas de `raw`**, no toca `staging`, las dimensiones ni `fact_sales`.

1. Dar a PostgreSQL permiso de lectura sobre `database/` (una vez por equipo) y validar los ocho CSV sin cargar nada:

```powershell
icacls database /grant "*S-1-5-20:(OI)(CI)RX"
python -m dotenv -f .env run -- dbt run-operation cargar_csv --profiles-dir . --target dev --args "{solo_validar: true}"
```

   Deben salir ocho líneas `CSV validado`. Si falla, no continuar. El usuario de `.env` debe ser superusuario de PostgreSQL, porque `COPY` lo exige.

2. En pgAdmin, conectado a **`dunnhumby_etl`** y sin el job en ejecución:

```sql
BEGIN;
DO $$
BEGIN
    IF current_database() <> 'dunnhumby_etl' THEN
        RAISE EXCEPTION 'Conectarse a dunnhumby_etl antes de borrar las tablas originales';
    END IF;
END $$;

DROP TABLE IF EXISTS
    raw.campaign_desc, raw.campaign_table, raw.causal_data, raw.coupon,
    raw.coupon_redempt, raw.hh_demographic, raw.product, raw.transaction_data;
COMMIT;
```

   El bloque no usa `CASCADE`. Si aparece un error por dependencias, ejecutar `ROLLBACK;` y compartir el mensaje.

3. Cargar los CSV en `raw` y construir `staging`:

```powershell
python -m dotenv -f .env run -- dbt build --profiles-dir . --target dev --select path:models/sincronizacion path:models/staging path:models/intermediate --vars "{cargar_csv: true}"
```

   Después construir el warehouse, con el segundo comando del paso 7.
4. Repetir las comprobaciones del paso 7: builds sin errores y los tres conteos.

La carga no reemplaza tablas existentes, por eso se borran antes. Las siguientes ejecuciones usan el build de `dev` **sin** `--vars "{cargar_csv: true}"`.

## 10. Excel y documentos

### Excel (ODBC)

Los libros de Excel hechos antes del cambio leen las tablas del esquema `public`, que ya no las tiene. Hay que apuntar cada consulta a `dw`. El origen ODBC `Dunnhumby_Excel` **no cambia**: sigue apuntando a la base `Data_warehouse`. Cada equipo debe tener ese origen creado (ver [conexion_excel_odbc.md](conexion_excel_odbc.md)); se comprueba en el administrador **Orígenes de datos ODBC (64 bits)**, pestaña **DSN de usuario**.

Para cada una de las cinco consultas (`dim_household`, `dim_product`, `dim_time`, `dim_promotional_context` y `fact_sales`):

1. En Excel, ir a **Datos → Consultas y conexiones** y hacer doble clic sobre la consulta. Se abre el Editor de Power Query.
2. En la cinta **Inicio**, pulsar **Editor avanzado**.
3. Buscar la línea que tiene `Kind="Schema"` y cambiar **solo** `Name="public"` por `Name="dw"`:

```text
let
    Origen = Odbc.DataSource("dsn=Dunnhumby_Excel", [HierarchicalNavigation=true]),
    Data_warehouse_Database = Origen{[Name="Data_warehouse",Kind="Database"]}[Data],
    public_Schema = Data_warehouse_Database{[Name="dw",Kind="Schema"]}[Data],
    dim_household_Table = public_Schema{[Name="dim_household",Kind="Table"]}[Data]
in
    dim_household_Table
```

   El nombre de la variable `public_Schema` puede quedar igual; solo importa el texto entre comillas después de `Name=`. Si la consulta tiene pasos adicionales, no reemplazar todo el código: cambiar únicamente esa palabra.

4. Pulsar **Listo** y luego **Cerrar y cargar**. Si Excel pide credenciales, elegir **Base de datos** e ingresar el usuario y la contraseña de PostgreSQL.

Al terminar, **Datos → Actualizar todo** y comprobar en **Consultas y conexiones** que las filas cargadas sean:

| Consulta | Filas |
| --- | ---: |
| `dim_household` | 2 500 |
| `dim_product` | 92 353 |
| `dim_time` | 711 |
| `dim_promotional_context` | 1 331 |
| `fact_sales` | 2 595 732 |

Además, revisar en **Datos → Relaciones** que `fact_sales` siga relacionada con las cuatro dimensiones, y probar una tabla dinámica para confirmar que las sumas tengan sentido. Si el libro se va a compartir, guardarlo (`Ctrl + S`) para que conserve los cambios, y dejar una sola versión corregida para el equipo.

El libro lee los datos de la base PostgreSQL del equipo donde se abre (`localhost`), no de otra computadora.

### Informe

Nombrar los esquemas como `raw` (CSV originales), `staging` (copias y vistas) y `dw` (modelo estrella).

## Si algo falla

| Mensaje | Qué hacer |
| --- | --- |
| `Conectarse a dunnhumby_etl` o `Conectarse a Data_warehouse` | Se ejecutó el script en la otra base. Cambiar de base y repetir. |
| `relation "public.xxx" does not exist` | Falta actualizar el proyecto o `profiles.yml` (pasos 3 y 4), o falta la migración (paso 5). |
| `... ya existe` al cargar los CSV | Las tablas ya están en `raw`. Para recargar, borrarlas primero (paso 9); si no, omitir `--vars "{cargar_csv: true}"`. |
| `PostgreSQL no puede leer ...` | Falta el permiso de lectura sobre `database/` (paso 9). |
| `Permission denied: ...yml` en el job | Falta el permiso del servicio sobre ese archivo (paso 8). |
| `relation "pgagent.pga_joblog" does not exist` | La consulta se ejecutó en otra base. Abrirla en `postgres`. |

Si un build falla, no ejecutar el siguiente paso: revisar el mensaje y compartirlo con el equipo.
