# Inicialización de dbt con PostgreSQL

## 1. Instalar dbt

Con PostgreSQL iniciado y el entorno virtual `venv` activo, ejecuta los
comandos en la terminal PowerShell de VS Code:

```powershell
cd C:\Proyecto_Mineria\proyectoDunnhumby
python -m pip install -r requirements-dbt.txt
dbt --version
```

## 2. Crear `.env`

Crea `.env` junto a `dbt_project.yml` desde la plantilla del repositorio:

```powershell
Copy-Item .env.example .env
```

Si `.env` ya existe, revisar sus valores sin sobrescribir las credenciales locales.
Completar `DBT_PG_USER` y `DBT_ENV_SECRET_PG_PASSWORD`, y ajustar host y puerto
si la configuración local es distinta. La plantilla contiene estos campos:

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

Escribe tu contraseña de PostgreSQL
entre las comillas simples; si contiene una comilla simple, escápala con `\'`.

`.env.example` se comparte en Git sin credenciales reales. Cada integrante
mantiene su `.env` local, que está excluido por `.gitignore`. Las variables de
conexión se utilizan tanto para dbt como para configurar `dblink` con
`conexion_warehouse.sql`; la base destino `Data_warehouse` está definida en el
target `warehouse` de la plantilla del perfil.

## 3. Crear `profiles.yml`

Crea `profiles.yml` junto a `dbt_project.yml` desde la plantilla del proyecto:

```powershell
Copy-Item profiles.example.yml profiles.yml
```

Si el perfil local ya existe, revisar sus conexiones sin sobrescribirlo.
La plantilla incluye `dev`, que apunta a `dunnhumby_etl.staging`, y `warehouse`,
que apunta a `Data_warehouse.public`. Ambas bases deben existir antes de comprobar
las conexiones. `.env` y `profiles.yml` están excluidos de Git.

## 4. Validar la conexión

Desde la carpeta del proyecto y con el entorno virtual activo, ejecuta:

```powershell
python -m dotenv -f .env run -- dbt debug --profiles-dir . --target dev

python -m dotenv -f .env run -- dbt debug --profiles-dir . --target warehouse
```

Comprueba que la salida de cada conexión incluya:

```text
profiles.yml file [OK found and valid]
dbt_project.yml file [OK found and valid]
Connection test: [OK connection ok]
All checks passed!
```

Guarda la salida o una captura, la fecha y la versión de dbt como evidencia
en Jira.

## 5. Volver a trabajar en otra sesión

Activa el entorno virtual, entra a la carpeta del proyecto y ejecuta:

```powershell
python -m dotenv -f .env run -- dbt debug --profiles-dir . --target dev

python -m dotenv -f .env run -- dbt debug --profiles-dir . --target warehouse
```

La contraseña se carga desde el `.env` guardado.

La configuración de lectura entre bases con `dblink` es un paso adicional,
documentado en el [flujo del README](../README.md#7-configurar-la-lectura-entre-las-dos-bases).
