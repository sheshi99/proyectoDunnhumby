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

Crea `.env` junto a `dbt_project.yml`. Copia estos campos, completa tu usuario
y contraseña y ajusta los demás valores si tu configuración local es distinta:

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

## 3. Crear `profiles.yml`

Crea `profiles.yml` junto a `dbt_project.yml` y copia este contenido:

```yaml
dunnhumby:
  target: "{{ env_var('DBT_TARGET') }}"
  outputs:
    dev:
      type: "{{ env_var('DBT_PG_TYPE') }}"
      host: "{{ env_var('DBT_PG_HOST') }}"
      port: "{{ env_var('DBT_PG_PORT') | int }}"
      user: "{{ env_var('DBT_PG_USER') }}"
      password: "{{ env_var('DBT_ENV_SECRET_PG_PASSWORD') }}"
      dbname: "{{ env_var('DBT_PG_DBNAME') }}"
      schema: "{{ env_var('DBT_PG_SCHEMA') }}"
      threads: "{{ env_var('DBT_THREADS') | int }}"
      connect_timeout: "{{ env_var('DBT_PG_CONNECT_TIMEOUT') | int }}"
```

## 4. Validar la conexión

Desde la carpeta del proyecto y con el entorno virtual activo, ejecuta:

```powershell
python -m dotenv -f .env run -- dbt debug --profiles-dir .
```

Comprueba que la salida incluya:

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
python -m dotenv -f .env run -- dbt debug --profiles-dir .
```

La contraseña se carga desde el `.env` guardado.
