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
   python -m pip install pandas psycopg2-binary sqlalchemy
   ```

   El primer grupo corresponde a dbt; el segundo, al cargador de CSV.
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

## 3. Cargar los CSV

Revisar en [cargar_bd.py](../scripts/cargar_bd.py) el usuario, host, puerto y
base. Por defecto usa `postgres`, `localhost:5432` y `dunnhumby_etl`. La
contraseña se pide en la terminal y no se escribe en el código.

```powershell
python scripts/cargar_bd.py
```

**Resultado esperado:** ocho tablas con sus registros en `dunnhumby_etl.public`.

> **Importante:** la carga reemplaza las tablas de `public`. Si ya están cargadas,
> no repetir este paso.

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

Siguiente paso: [copiar las tablas a staging](capa_staging.md).
