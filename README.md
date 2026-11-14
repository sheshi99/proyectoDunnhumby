# Proyecto Dunnhumby

Proyecto de integración con PostgreSQL y dbt. Una macro dbt ejecuta `COPY` para
cargar los CSV en la base de origen; los modelos dbt transforman los datos y
construyen el almacén. Los datos originales del dataset Dunnhumby se
conservan en una base de trabajo y los modelos dbt construyen un modelo estrella
(cuatro dimensiones y una tabla de hechos) en otra base. Un job de pgAgent
mantiene el warehouse actualizado cada madrugada, a las 2:00 a. m.

## Organización de los datos

| Base de datos | Esquema | Contenido |
| --- | --- | --- |
| `dunnhumby_etl` | `public` | Ocho tablas originales cargadas desde los CSV. |
| `dunnhumby_etl` | `staging` | Copias de trabajo, ocho vistas limpias `stg_` y tres vistas intermedias `int_` (hogares, calendario y contexto promocional). |
| `Data_warehouse` | `public` | Cuatro dimensiones y la tabla de hechos `fact_sales`. |

```text
CSV → public → copias en staging → vistas stg_ → dimensiones y hechos → job diario 2:00 a. m.
```

## Cómo usar esta guía

Para instalar el proyecto desde cero, seguir los pasos en orden. Cada paso
resume qué se hace y qué resultado se espera, y enlaza a la guía con los
comandos y el detalle. Si una etapa ya está completa en tu equipo, comprobar su
resultado y pasar a la siguiente.

Antes de empezar:

- Los comandos de terminal se ejecutan en PowerShell desde la raíz del repositorio.
- Usar el mismo usuario de PostgreSQL en todos los pasos (carga, permisos, `.env`
  y `psql`). Ese usuario debe ser superusuario de PostgreSQL (como `postgres`):
  debe poder crear bases, roles, extensiones y tablas, y ejecutar `COPY` desde archivos.
- Algunos comandos están divididos en varias líneas con el acento grave (`` ` ``)
  de PowerShell. Se copia el bloque completo; no dejar espacios después de ese carácter.
- Las consultas SQL se ejecutan en **pgAdmin → Query Tool**, conectado a la base
  que indica cada guía.

## Instalación desde cero

### 1. Preparar el entorno y los CSV

Se necesitan PostgreSQL, pgAdmin, `psql` en la terminal y Python. Se crea el
entorno virtual `venv`, se instalan las dependencias de dbt, y se
colocan los ocho CSV en `database/` (no están en Git).

Guía: [Preparación de las bases y carga de datos](docs/instrucciones_de_carga.md), sección 1.

### 2. Crear las bases y cargar los datos originales

Se crean las bases `dunnhumby_etl` y `Data_warehouse`, se configuran las conexiones
dbt y la macro `cargar_csv` carga los CSV en `dunnhumby_etl.public` mediante
`COPY`, leyendo directamente la carpeta `database/` (dbt la encuentra sola).
Una vez por equipo hay que dar al servicio PostgreSQL permiso de lectura sobre
esa carpeta: `icacls database /grant "*S-1-5-20:(OI)(CI)RX"`.
**La macro no reemplaza tablas existentes por defecto.** Ver [carga CSV con dbt](docs/carga_csv_dbt.md).

Guía: [Preparación de las bases y carga de datos](docs/instrucciones_de_carga.md), secciones 2 y 3.

### 3. Revisar la calidad de los datos

Las consultas de `scripts/sql/RevisionCalidad/` muestran los problemas de cada
tabla. Sus conclusiones justifican las transformaciones de las vistas limpias.

Guía: [Preparación de las bases y carga de datos](docs/instrucciones_de_carga.md), sección 4.

### 4. Configurar roles y permisos

Dos scripts crean los roles `rol_staging` y `rol_data_warehouse` con sus permisos,
uno en cada base.

Guía: [Preparación de las bases y carga de datos](docs/instrucciones_de_carga.md), sección 5.

### 5. Configurar las conexiones de dbt

Se crean los archivos locales `.env` y `profiles.yml` desde sus plantillas y se
comprueban las dos conexiones: `dev` (staging) y `warehouse` (Data_warehouse).
Las credenciales no se suben a Git.

Guía: [Inicialización de dbt](docs/inicializacion_dbt.md), secciones 1 a 4.

### 6. Configurar la lectura entre las dos bases

`Data_warehouse` necesita leer las vistas de `dunnhumby_etl`. Se configura
`dblink` con `psql` usando las variables de `.env`.

Guía: [Inicialización de dbt](docs/inicializacion_dbt.md), sección 5.

### 7. Copiar las tablas originales a staging

dbt copia las ocho tablas de `public` a `staging`, donde trabaja, y se
validan los requisitos. `public` queda intacto.

Guía: [Capa staging](docs/capa_staging.md), sección 1.

### 8. Crear las vistas limpias

dbt crea en `staging` las ocho vistas `stg_` y las vistas intermedias
`int_household`, `int_time` e `int_sales_promotional_context`, y ejecuta sus pruebas.

Guía: [Capa staging](docs/capa_staging.md), sección 2. Para agregar o modificar
una vista, ver la sección 3 de la misma guía.

### 9. Crear y cargar el modelo estrella

dbt crea las cuatro dimensiones y la tabla de hechos con sus claves, las carga
y ejecuta sus pruebas. Todo el modelo estrella se construye con dbt.

Guía: [Modelo estrella](docs/guia_modelo_estrella_dbt.md), sección 7 (ejecución).
El detalle de las dimensiones está en las secciones 1 y 6, y el de la tabla de
ventas en las secciones 2 a 5.

### 10. Validar el resultado

Se revisan las tablas creadas, una muestra de ventas y se compara el conteo de
`fact_sales` con las transacciones de staging. Las pruebas no deben mostrar
`FAIL` ni `ERROR`.

Guía: [Modelo estrella](docs/guia_modelo_estrella_dbt.md), sección 8 (validación).

### 11. Activar la actualización automática

El job **`Dunnhumby_ETL_madrugada`** de pgAgent se ejecuta todos los días a las
2:00 a. m.: sincroniza las copias de staging con `public` y luego compara staging
con el warehouse, aplicando solo las diferencias. Los datos nuevos se cargan en
`public`.

Guía: [Ejecución y configuración del job ETL](docs/job_etl.md).

- Secciones 4 y 5: qué hace cada ejecución, cómo se conservan los IDs y cómo
  revisar los resultados.
- Secciones 1 a 3 y 6: componentes, requisitos y pasos para instalar pgAgent en
  otro equipo o reconfigurarlo.

## Reconstruir las tablas desde cero

Este procedimiento queda preparado para ejecutarlo cuando se decida reconstruir.
Conservar los ocho CSV de `database/`, `.env`, `profiles.yml`, las dos bases
`dunnhumby_etl` y `Data_warehouse`, y sus esquemas `public`. Si se eliminan también
las bases o esos esquemas, primero deben crearse de nuevo según la guía de carga.

Si se conservaron los roles y la configuración de `dblink`, usar directamente
`dbt build`. Con `venv` activado y desde la raíz del proyecto:

```powershell
python -m dotenv -f .env run -- dbt build --profiles-dir . --target dev --select path:models/sincronizacion path:models/staging path:models/intermediate --vars "{cargar_csv: true}"

python -m dotenv -f .env run -- dbt build --profiles-dir . --target warehouse --select path:models/dimensions path:models/facts
```

El primer build carga los ocho CSV en `public` mediante un hook de inicio y
después construye staging y sus vistas. El segundo construye las dimensiones y
los hechos. Ejecutar el segundo solo si el primero termina correctamente.
Los CSV se leen de la carpeta `database/` del proyecto; antes, una vez por
equipo, dar permiso de lectura al servicio PostgreSQL
(`icacls database /grant "*S-1-5-20:(OI)(CI)RX"`). En ejecuciones posteriores omitir `--vars "{cargar_csv: true}"`:
sin esa variable no se cargan los CSV ni se reemplazan las tablas originales.

Como alternativa, las etapas pueden ejecutarse por separado (no repetir la carga
si ya se usó el primer build con `cargar_csv: true`):

1. Ejecutar `dbt run-operation cargar_csv --target dev`, con las variables de
   `.env` y `--profiles-dir .`: carga las ocho tablas originales de `database/`
   en `dunnhumby_etl.public`.
2. Configurar los roles con `staging_roles_permisos.sql` y
   `warehouse_roles_permisos.sql`, y la lectura entre bases con
   `conexion_warehouse.sql`, como indican las guías. Estos scripts permiten
   restablecer la configuración si se borró.
3. Ejecutar `dbt build --target dev --select path:models/sincronizacion
   path:models/staging path:models/intermediate`, con las variables de `.env`
   y `--profiles-dir .`: crea las copias de staging y las vistas.
4. Ejecutar `dbt build --target warehouse --select path:models/dimensions
   path:models/facts`, con las mismas variables y perfil: crea las dimensiones
   y `fact_sales`, y ejecuta las pruebas dbt.

No usar `--full-refresh`: el modelo crea las tablas cuando no existen.
La carga inicial de CSV no se ejecuta automáticamente por el job diario.

## Estructura del proyecto

| Carpeta o archivo | Contenido |
| --- | --- |
| `database/` | CSV locales, excluidos de Git. |
| `macros/cargar_csv.sql` | Carga inicial de CSV mediante dbt y PostgreSQL COPY. |
| `macros/cargar_csv_al_iniciar.sql` | Hook que ejecuta la carga en `dbt build` con `cargar_csv: true`. |
| `scripts/sql/` | Configuración, revisión de calidad, copia y validación de staging. |
| `scripts/preparar_pgagent.ps1` | Comprobación y generación de los comandos del job. |
| `scripts/registrar_pgagent.ps1` | Registro del servicio y del job en pgAgent. |
| `scripts/ejecutar_dbt_pgagent.ps1` | Lanzador del job: dbt, limpieza de dimensiones y logs. |
| `models/sources/` | Declaraciones de las tablas que dbt usa como entrada. |
| `models/sincronizacion/` | Copia y sincronización de las tablas de `public` en `staging`. |
| `models/staging/` | Modelos de las vistas limpias. |
| `models/intermediate/` | Preparación de hogares (`int_household`), calendario (`int_time`) y contexto promocional de las ventas (`int_sales_promotional_context`). |
| `models/dimensions/` | Modelos de las cuatro dimensiones. |
| `models/facts/` | Modelo y pruebas de la tabla de hechos. |
| `macros/` | Lectura entre bases, actualización por diferencias y limpieza de dimensiones. |
| `docs/` | Guías detalladas de cada etapa. |
| `profiles.example.yml` | Plantilla de las dos conexiones dbt. |
| `.env.example` | Plantilla de variables de entorno, sin credenciales reales. |
