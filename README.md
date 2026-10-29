# Proyecto Dunnhumby

Proyecto ETL con PostgreSQL y dbt. Los datos originales se conservan en una base
de trabajo y los modelos dbt construyen las dimensiones y hechos en otra base.


## Organización de los datos

| Base de datos | Esquema | Contenido |
| --- | --- | --- |
| `dunnhumby_etl` | `public` | Ocho tablas originales cargadas desde los CSV. |
| `dunnhumby_etl` | `staging` | Copias de trabajo, ocho vistas limpias `stg_` y la vista intermedia de contexto promocional. |
| `Data_warehouse` | `public` | Cuatro dimensiones y la tabla de hechos `fact_sales`. |

El proceso sigue este orden: carga original → copia a staging → vistas limpias
→ dimensiones y hechos → validación.

## Preparación inicial

Los pasos siguientes se realizan para preparar una instalación del proyecto.
Si una etapa ya está completa, comprobar su resultado y continuar con la siguiente.
Los comandos de terminal se ejecutan en PowerShell desde la raíz del repositorio.
Para reproducir la configuración, utilizar el mismo usuario PostgreSQL en el
cargador, los scripts de permisos, `.env` y la conexión `psql`. Ese usuario debe
tener permisos para crear las bases, roles, extensión y objetos del proyecto.

### 1. Preparar el entorno y los archivos de datos

Se necesita PostgreSQL activo, pgAdmin, `psql` disponible en la terminal y Python
con soporte para crear un entorno virtual. Colocar los ocho CSV del dataset en
`database/`; esos archivos no se incluyen en Git.

Si todavía no existe un entorno virtual:

```powershell
python -m venv venv
```

Activar el entorno e instalar las dependencias:

```powershell
.\venv\Scripts\Activate.ps1

python -m pip install -r requirements-dbt.txt
python -m pip install pandas psycopg2-binary sqlalchemy
```

El primer grupo de dependencias corresponde a dbt; el segundo, al cargador de CSV.

### 2. Crear las dos bases de datos

En pgAdmin, abrir Query Tool conectado a `postgres` con un usuario administrador.
Ejecutar cada sentencia por separado, fuera de una transacción, solo si la base
todavía no existe:

```sql
CREATE DATABASE dunnhumby_etl;
```

```sql
CREATE DATABASE "Data_warehouse";
```

Las comillas conservan el nombre exacto `Data_warehouse`, utilizado por la conexión
de dbt. Al terminar, ambas bases deben aparecer en pgAdmin.

### 3. Cargar los originales y revisar su calidad

Revisar el usuario y los datos de conexión en [cargar_bd.py](scripts/cargar_bd.py).
El cargador actual usa `postgres`, `localhost:5432` y `dunnhumby_etl`, y solicita
la contraseña en la terminal.

```powershell
python scripts/cargar_bd.py
```

**La carga reemplaza las tablas de origen. Si los ocho CSV ya están cargados,
no repetir este comando para continuar con el modelado.**

Con Query Tool conectado a `dunnhumby_etl`, ejecutar las consultas de
`scripts/sql/RevisionCalidad/` para inspeccionar las ocho tablas de `public`.
La [guía de carga](docs/instrucciones_de_carga.md) detalla esta preparación.

### 4. Configurar los esquemas, roles y permisos

Abrir cada archivo SQL en Query Tool, seleccionando la base indicada:

| Base seleccionada | Archivo que se ejecuta completo |
| --- | --- |
| `dunnhumby_etl` | [staging_roles_permisos.sql](scripts/sql/Configuraciones/staging_roles_permisos.sql) |
| `Data_warehouse` | [warehouse_roles_permisos.sql](scripts/sql/Configuraciones/warehouse_roles_permisos.sql) |

Usar el usuario que creará los objetos dbt, con los permisos administrativos
necesarios para ejecutar estos scripts. Configuran los roles `rol_staging` y
`rol_data_warehouse`, sus permisos y los permisos predeterminados para objetos
futuros. Verificar que los resultados muestren la base, el esquema y el rol
correspondientes; las comprobaciones de permisos del warehouse deben devolver `true`.

### 5. Copiar las ocho tablas a staging

Con Query Tool conectado a **`dunnhumby_etl`**, ejecutar en este orden:

1. [copiar_tablas_a_staging.sql](scripts/sql/staging/copiar_tablas_a_staging.sql).
2. [00_validar_requisitos.sql](scripts/sql/staging/00_validar_requisitos.sql).

La copia conserva nombres, tipos y registros. Si las tablas destino ya existen,
el script se detiene sin sobrescribirlas. Si las ocho copias ya están completas,
continuar con la validación de requisitos.

**Resultado esperado:** ocho tablas físicas en `dunnhumby_etl.staging`, disponibles
para el usuario de dbt. Esta copia inicial no se actualiza automáticamente cuando
cambia `public`. Ver la [guía de staging](docs/capa_staging.md).

### 6. Configurar y comprobar las conexiones de dbt

Crear los archivos locales desde las plantillas si todavía no existen:

```powershell
Copy-Item .env.example .env
Copy-Item profiles.example.yml profiles.yml
```

Completar `DBT_PG_USER` y `DBT_ENV_SECRET_PG_PASSWORD` en `.env`, y revisar host y
puerto según la [guía de inicialización](docs/inicializacion_dbt.md). El usuario
debe poder trabajar con las dos bases. El cargador de CSV mantiene su propia
configuración en `scripts/cargar_bd.py`.

Si `.env` o `profiles.yml` ya existen, revisar su contenido sin sobrescribir la
configuración local. El perfil debe incluir ambas conexiones:

| Target de dbt | Destino |
| --- | --- |
| `dev` | `dunnhumby_etl.staging`, para preparar las vistas. |
| `warehouse` | `Data_warehouse.public`, para construir dimensiones y hechos. |

Comprobar cada conexión:

```powershell
python -m dotenv -f .env run -- dbt debug --profiles-dir . --target dev

python -m dotenv -f .env run -- dbt debug --profiles-dir . --target warehouse
```

Ambas deben indicar `Connection test: ... connection ok`. `.env` y `profiles.yml`
son archivos locales excluidos de Git; no se publican las credenciales.
Las plantillas `.env.example` y `profiles.example.yml` sí se incluyen en Git
para que cada integrante prepare su entorno sin compartir contraseñas.

### 7. Configurar la lectura entre las dos bases

La conexión `warehouse` necesita consultar las vistas de la primera base.
[conexion_warehouse.sql](scripts/sql/Configuraciones/conexion_warehouse.sql)
configura `dblink` para ese acceso. Este archivo se ejecuta con **`psql`**, porque
usa instrucciones para leer variables del entorno.

En el siguiente comando, sustituir `USUARIO_DBT` por el usuario configurado en
`DBT_PG_USER`. Ajustar host y puerto si no son `localhost:5432`:

```powershell
python -m dotenv -f .env run -- psql `
    --host=localhost `
    --port=5432 `
    --username=USUARIO_DBT `
    --dbname=Data_warehouse `
    --password `
    --file=scripts/sql/Configuraciones/conexion_warehouse.sql
```

Ingresar la contraseña cuando la solicite `psql`. El usuario requiere permisos
para configurar la extensión y el servidor de conexión. Este paso configura el
acceso; las tablas finales se crean después con dbt.

Los comandos divididos en líneas usan el acento grave de PowerShell al final de
cada línea que continúa. No colocar espacios después de ese carácter.

## Construcción del modelo con dbt

Con la preparación anterior completa, ejecutar estos pasos en orden. Cada comando
debe terminar correctamente antes de iniciar el siguiente.

### 8. Crear las vistas limpias y el contexto promocional

```powershell
python -m dotenv -f .env run -- dbt run `
    --profiles-dir . `
    --target dev `
    --select path:models/staging path:models/intermediate
```

**Resultado esperado:** ocho vistas `stg_` y la vista
`int_sales_promotional_context` en `dunnhumby_etl.staging`.

Ejecutar las pruebas de las vistas:

```powershell
python -m dotenv -f .env run -- dbt test `
    --profiles-dir . `
    --target dev `
    --select path:models/staging
```

Como comprobación adicional, ejecutar
[03_validar_staging.sql](scripts/sql/staging/03_validar_staging.sql) en Query Tool
de `dunnhumby_etl`. Ese script comprueba específicamente las vistas de transacciones
y datos causales; no sustituye las pruebas de los demás modelos.

El [instructivo de modelos de staging](docs/instructivo_dbt_ETL.md) explica cómo
agregar o modificar una vista de limpieza.

### 9. Crear las dimensiones y la tabla de hechos

```powershell
python -m dotenv -f .env run -- dbt build `
    --profiles-dir . `
    --target warehouse `
    --select path:models/dimensions path:models/facts
```

**Resultado esperado:** las siguientes tablas en `Data_warehouse.public`:

- `dim_product`
- `dim_household`
- `dim_time`
- `dim_promotional_context`
- `fact_sales`

`dbt build` crea las tablas y ejecuta sus pruebas. La carga es completa y puede
tardar varios minutos. Se reconstruyen dimensiones y hechos juntos porque los
IDs propios del contexto promocional pueden cambiar.

Utilizar la selección indicada: ejecutar todos los modelos con `warehouse`, o usar
`+` para incluir sus dependencias, puede crear vistas de preparación en el destino.

Consultar la [guía de dimensiones](docs/guia_dimensiones_dbt.md) y la
[guía de hechos](docs/guia_hechos_dbt.md) para entender las transformaciones,
identificadores y relaciones.

### 10. Revisar las tablas finales

Con Query Tool conectado a **`Data_warehouse`**, ejecutar:

```sql
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_type = 'BASE TABLE'
ORDER BY table_name;
```

Revisar una muestra y el conteo de hechos:

```sql
SELECT *
FROM public.fact_sales
LIMIT 10;

SELECT count(*) AS filas_hechos
FROM public.fact_sales;
```

La guía de hechos explica cómo comparar ese conteo con las transacciones de
staging. Las pruebas deben terminar sin `FAIL` ni `ERROR`.

### 11. Programar la actualización cada dos horas

Con el flujo anterior preparado, ejecutar una vez el proceso completo:

```powershell
python scripts/ejecutar_job.py
```

Este proceso actualiza las ocho tablas de staging desde `public`, ejecuta dbt
con sus pruebas en ambas conexiones y compara las medidas de hechos con staging.
El resultado debe ser `CORRECTO` en `logs/jobs/ultima_ejecucion.json`.

Registrar la tarea desde la cuenta de Windows que utilizará el proyecto:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\registrar_job.ps1 `
    -PythonExecutable (Get-Command python).Source
```

La tarea **`Dunnhumby_ETL_cada_2_horas`** se registra en el **Programador de tareas
de Windows** y empieza a ejecutarse dos horas después del registro. Utiliza dbt
para las transformaciones y trabaja con `dunnhumby_etl` y `Data_warehouse`.
El equipo debe estar encendido, PostgreSQL disponible y la cuenta de Windows
debe mantener una sesión iniciada. Se puede bloquear la pantalla.

Los resultados se guardan en `logs/jobs/`, excluido de Git. La
[guía del job](docs/job_etl.md) explica las etapas, las comprobaciones de registro
y los comandos para consultar, iniciar o desactivar la tarea. Si ya está
registrada y activa en ese equipo, no hace falta repetir la instalación.

## Estructura del proyecto

| Carpeta o archivo | Contenido |
| --- | --- |
| `database/` | CSV locales, excluidos de Git. |
| `scripts/cargar_bd.py` | Carga original desde CSV a PostgreSQL. |
| `scripts/ejecutar_job.py` | Actualización completa de staging y ejecución de dbt con validaciones. |
| `scripts/registrar_job.ps1` | Registro y comprobación de la tarea de Windows cada dos horas. |
| `scripts/sql/` | Configuración, revisión de calidad, copia y validación de staging. |
| `models/sources/` | Declaraciones de las tablas que dbt usa como entrada. |
| `models/staging/` | Modelos de las vistas limpias. |
| `models/intermediate/` | Preparación del contexto promocional de las ventas. |
| `models/dimensions/` | Modelos de las cuatro dimensiones. |
| `models/facts/` | Modelo y pruebas de la tabla de hechos. |
| `macros/` | Funciones reutilizables de dbt para lectura entre bases y configuración. |
| `docs/` | Guías detalladas de cada etapa. |
| `profiles.example.yml` | Plantilla de las dos conexiones dbt. |
| `.env.example` | Plantilla de variables de entorno, sin credenciales reales. |
