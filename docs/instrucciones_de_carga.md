# Preparación de las bases y carga de datos

Esta guía cubre los pasos 1 a 4 del [README](../README.md): preparar el entorno,
crear las bases, cargar los CSV, revisar su calidad y configurar los permisos.

## 1. Preparar el entorno y los CSV

Requisitos: PostgreSQL activo, pgAdmin, `psql` disponible en la terminal y Python.

1. Obtener la versión más reciente del repositorio:

   ```powershell
   git checkout main
   git pull
   ```

2. Crear el entorno virtual (solo la primera vez), activarlo e instalar las
   dependencias:

   ```powershell
   python -m venv venv
   .\venv\Scripts\Activate.ps1

   python -m pip install -r requirements-dbt.txt
   ```

   Estas dependencias incluyen dbt, el adaptador PostgreSQL y dotenv.
   La nueva carga no necesita pandas ni SQLAlchemy.
   Si PowerShell bloquea `Activate.ps1` o Python muestra errores de permisos,
   abrir VS Code como administrador y repetir el comando.

3. Copiar los ocho CSV del dataset Dunnhumby en la carpeta `database/` del
   proyecto. Esta carpeta está excluida de Git por el tamaño de los archivos.

## 2. Crear las dos bases de datos

En pgAdmin, abrir Query Tool conectado a `postgres`. Ejecutar cada sentencia por
separado, solo si la base todavía no existe:

```sql
CREATE DATABASE dunnhumby_etl;
```

```sql
CREATE DATABASE "Data_warehouse";
```

Las comillas conservan el nombre exacto `Data_warehouse`, que usa la conexión de
dbt. Al terminar, ambas bases deben aparecer en pgAdmin.

## 3. Cargar los CSV mediante dbt

Antes de cargar, configurar `.env` y `profiles.yml` y comprobar la conexión
`dev`, siguiendo las secciones 1 a 4 de [inicializacion_dbt.md](inicializacion_dbt.md).
No ejecutar todavía su sección de `dblink`.

La macro [cargar_csv.sql](../macros/cargar_csv.sql) usa `COPY` de PostgreSQL para
leer los ocho CSV de la carpeta `database/` del proyecto; la encuentra sola.

1. Una vez por equipo, dar al servicio PostgreSQL permiso de lectura sobre
   `database/` (desde la raíz del proyecto, en PowerShell):

   ```powershell
   icacls database /grant "*S-1-5-20:(OI)(CI)RX"
   ```

2. Cargar los CSV (con `venv` activado). El usuario de `.env` debe ser
   superusuario de PostgreSQL, porque `COPY` desde archivos lo exige. Solo carga `public`; no construye modelos:

   ```powershell
   python -m dotenv -f .env run -- dbt run-operation cargar_csv --profiles-dir . --target dev
   ```

   Para solo comprobar los archivos, sin cargar: agregar `--args "{solo_validar: true}"`.

Si los roles de staging ya están configurados (por ejemplo, al reconstruir), la
carga también puede hacerse dentro del primer `dbt build` con
`--vars "{cargar_csv: true}"`; ver [carga CSV con dbt](carga_csv_dbt.md#2-cargar-los-csv).

**Resultado esperado:** ocho tablas con sus registros en `dunnhumby_etl.public`.
Si ya existen, la macro se detiene sin sustituirlas.

La guía [carga CSV con dbt](carga_csv_dbt.md) explica los requisitos, las
protecciones, las rutas con tildes y cómo volver atrás.
Después, continuar con las secciones 4 y 5 de esta guía y configurar `dblink`
según la sección 5 de inicialización de dbt.

## 4. Revisar la calidad de los datos

Con Query Tool conectado a `dunnhumby_etl`, ejecutar las consultas de
`scripts/sql/RevisionCalidad/`, una por tabla. Cada archivo indica qué problemas
se encontraron y qué acciones se proponen. Estas conclusiones son la base de
las transformaciones de las vistas limpias.

## 5. Configurar roles y permisos

Abrir cada archivo en Query Tool, conectado a la base indicada, y ejecutarlo
completo:

| Base seleccionada | Archivo |
| --- | --- |
| `dunnhumby_etl` | [staging_roles_permisos.sql](../scripts/sql/Configuraciones/staging_roles_permisos.sql) |
| `Data_warehouse` | [warehouse_roles_permisos.sql](../scripts/sql/Configuraciones/warehouse_roles_permisos.sql) |

Crean los roles `rol_staging` y `rol_data_warehouse`, sus permisos y los permisos
predeterminados para objetos futuros.

**Resultado esperado:** los resultados muestran la base, el esquema y el rol
correspondientes, y las comprobaciones del warehouse devuelven `true`.

Siguiente paso: [configurar las conexiones de dbt](inicializacion_dbt.md).
