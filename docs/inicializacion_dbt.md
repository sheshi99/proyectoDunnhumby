# Inicialización de dbt con PostgreSQL

Esta guía cubre los pasos 6 y 7 del [README](../README.md): configurar las
conexiones de dbt y la lectura entre las dos bases. Requiere el entorno virtual
activo y las dependencias de `requirements-dbt.txt` instaladas
([preparación del entorno](instrucciones_de_carga.md)).

## 1. Comprobar dbt

```powershell
dbt --version
```

Debe mostrar dbt Core y el adaptador `postgres`.

## 2. Crear `.env`

Crear `.env` junto a `dbt_project.yml` desde la plantilla. Si ya existe, revisar
sus valores sin sobrescribirlo.

```powershell
Copy-Item .env.example .env
```

Completar `DBT_PG_USER` y `DBT_ENV_SECRET_PG_PASSWORD`, y ajustar host y puerto
si la configuración local es distinta:

```dotenv
DBT_PG_HOST=localhost
DBT_PG_PORT=5432
DBT_PG_USER=
DBT_ENV_SECRET_PG_PASSWORD=''
DBT_PG_DBNAME=dunnhumby_etl
DBT_PG_SCHEMA=staging
DBT_TARGET=dev
DBT_PG_TYPE=postgres
DBT_THREADS=4
DBT_PG_CONNECT_TIMEOUT=10
```

La contraseña va entre comillas simples; si contiene una comilla simple,
escribirla como `\'`.

Estas variables se usan en dbt, en la configuración de `dblink` (sección 5) y
en el job de pgAgent. Cada integrante mantiene su `.env` local; está excluido de
Git y no se comparte.

## 3. Crear `profiles.yml`

Crear `profiles.yml` junto a `dbt_project.yml` desde la plantilla. Si ya existe,
revisar sus conexiones sin sobrescribirlo.

```powershell
Copy-Item profiles.example.yml profiles.yml
```

El perfil tiene dos conexiones (targets):

| Target | Destino | Uso |
| --- | --- | --- |
| `dev` | `dunnhumby_etl.staging` | Vistas limpias y contexto promocional. |
| `warehouse` | `Data_warehouse.public` | Dimensiones y hechos. |

`profiles.yml` también está excluido de Git.

## 4. Validar las conexiones

```powershell
python -m dotenv -f .env run -- dbt debug --profiles-dir . --target dev

python -m dotenv -f .env run -- dbt debug --profiles-dir . --target warehouse
```

`python -m dotenv -f .env run --` carga las variables de `.env` antes de ejecutar
dbt. Cada conexión debe terminar con:

```text
Connection test: [OK connection ok]
All checks passed!
```

## 5. Configurar la lectura entre las dos bases

Los modelos del warehouse leen las vistas de `dunnhumby_etl.staging` mediante
`dblink`. [conexion_warehouse.sql](../scripts/sql/Configuraciones/conexion_warehouse.sql)
configura la extensión y el servidor de conexión. Se ejecuta con `psql`, no con
pgAdmin, porque lee las variables de `.env`.

Sustituir `USUARIO_DBT` por el valor de `DBT_PG_USER`, y ajustar host y puerto
si no son `localhost:5432`:

```powershell
python -m dotenv -f .env run -- psql `
    --host=localhost `
    --port=5432 `
    --username=USUARIO_DBT `
    --dbname=Data_warehouse `
    --password `
    --file=scripts/sql/Configuraciones/conexion_warehouse.sql
```

Ingresar la contraseña cuando `psql` la solicite. Este paso solo configura el
acceso; las tablas se crean después.

## Al volver a trabajar

Abrir PowerShell en la raíz del proyecto y activar el entorno:

```powershell
.\venv\Scripts\Activate.ps1
```

Las credenciales se cargan desde `.env` en cada comando; no hace falta
configurarlas de nuevo.

Siguiente paso: [crear las vistas limpias](capa_staging.md#2-crear-las-vistas-limpias).
