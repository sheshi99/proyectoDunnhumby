# Proyecto Dunnhumby

Proyecto ETL con PostgreSQL y dbt. Los datos originales del dataset Dunnhumby se
conservan en una base de trabajo y los modelos dbt construyen un modelo estrella
(cuatro dimensiones y una tabla de hechos) en otra base. Un job de pgAgent
mantiene el warehouse actualizado cada dos horas.

## Organización de los datos

| Base de datos | Esquema | Contenido |
| --- | --- | --- |
| `dunnhumby_etl` | `public` | Ocho tablas originales cargadas desde los CSV. |
| `dunnhumby_etl` | `staging` | Copias de trabajo, ocho vistas limpias `stg_` y la vista intermedia de contexto promocional. |
| `Data_warehouse` | `public` | Cuatro dimensiones y la tabla de hechos `fact_sales`. |

```text
CSV → public → copias en staging → vistas stg_ → dimensiones y hechos → job cada dos horas
```

## Cómo usar esta guía

Para instalar el proyecto desde cero, seguir los pasos en orden. Cada paso
resume qué se hace y qué resultado se espera, y enlaza a la guía con los
comandos y el detalle. Si una etapa ya está completa en tu equipo, comprobar su
resultado y pasar a la siguiente.

Antes de empezar:

- Los comandos de terminal se ejecutan en PowerShell desde la raíz del repositorio.
- Usar el mismo usuario de PostgreSQL en todos los pasos (carga, permisos, `.env`
  y `psql`). Ese usuario debe poder crear bases, roles, extensiones y tablas.
- Algunos comandos están divididos en varias líneas con el acento grave (`` ` ``)
  de PowerShell. Se copia el bloque completo; no dejar espacios después de ese carácter.
- Las consultas SQL se ejecutan en **pgAdmin → Query Tool**, conectado a la base
  que indica cada guía.

## Instalación desde cero

### 1. Preparar el entorno y los CSV

Se necesitan PostgreSQL, pgAdmin, `psql` en la terminal y Python. Se crea el
entorno virtual `venv`, se instalan las dependencias de dbt y del cargador, y se
colocan los ocho CSV en `database/` (no están en Git).

Guía: [Preparación de las bases y carga de datos](docs/instrucciones_de_carga.md), sección 1.

### 2. Crear las bases y cargar los datos originales

Se crean las bases `dunnhumby_etl` y `Data_warehouse`, y el script
`cargar_bd.py` carga los CSV en `dunnhumby_etl.public`.
**La carga reemplaza las tablas de origen: no repetirla si ya están cargadas.**

Guía: [Preparación de las bases y carga de datos](docs/instrucciones_de_carga.md), secciones 2 y 3.

### 3. Revisar la calidad de los datos

Las consultas de `scripts/sql/RevisionCalidad/` muestran los problemas de cada
tabla. Sus conclusiones justifican las transformaciones de las vistas limpias.

Guía: [Preparación de las bases y carga de datos](docs/instrucciones_de_carga.md), sección 4.

### 4. Configurar roles y permisos

Dos scripts crean los roles `rol_staging` y `rol_data_warehouse` con sus permisos,
uno en cada base.

Guía: [Preparación de las bases y carga de datos](docs/instrucciones_de_carga.md), sección 5.

### 5. Copiar las tablas originales a staging

Se copian las ocho tablas de `public` a `staging`, donde trabaja dbt, y se
validan los requisitos. `public` queda intacto.

Guía: [Capa staging](docs/capa_staging.md), sección 1.

### 6. Configurar las conexiones de dbt

Se crean los archivos locales `.env` y `profiles.yml` desde sus plantillas y se
comprueban las dos conexiones: `dev` (staging) y `warehouse` (Data_warehouse).
Las credenciales no se suben a Git.

Guía: [Inicialización de dbt](docs/inicializacion_dbt.md), secciones 1 a 4.

### 7. Configurar la lectura entre las dos bases

`Data_warehouse` necesita leer las vistas de `dunnhumby_etl`. Se configura
`dblink` con `psql` usando las variables de `.env`.

Guía: [Inicialización de dbt](docs/inicializacion_dbt.md), sección 5.

### 8. Crear las vistas limpias

dbt crea en `staging` las ocho vistas `stg_` y la vista
`int_sales_promotional_context`, y ejecuta sus pruebas.

Guía: [Capa staging](docs/capa_staging.md), sección 2. Para agregar o modificar
una vista, ver el [instructivo de modelos de staging](docs/instructivo_dbt_ETL.md).

### 9. Crear y cargar el modelo estrella

Se crean las tablas vacías con `star_schema.sql` y dbt las carga con las
dimensiones y la tabla de hechos, ejecutando sus pruebas.

Guía: [Dimensiones](docs/guia_dimensiones_dbt.md), sección 3 (ejecución).
El detalle de la tabla de ventas está en la [guía de hechos](docs/guia_hechos_dbt.md).

### 10. Validar el resultado

Se revisan las tablas creadas, una muestra de ventas y se compara el conteo de
`fact_sales` con las transacciones de staging. Las pruebas no deben mostrar
`FAIL` ni `ERROR`.

Guía: [Hechos](docs/guia_hechos_dbt.md), sección 5 (validación).

### 11. Activar la actualización automática

El job **`Dunnhumby_ETL_cada_2_horas`** de pgAgent compara cada dos horas las
copias de staging con el warehouse y aplica solo las diferencias. No modifica
staging: los datos nuevos deben estar cargados antes ahí. En la instalación
actual ya está activo.

- [Funcionamiento del job](docs/job_etl.md): qué hace cada ejecución, cómo se
  conservan los IDs y cómo revisar los resultados.
- [Configuración de pgAgent](docs/pgagent.md): pasos para instalarlo en otro
  equipo o reconfigurarlo.

## Estructura del proyecto

| Carpeta o archivo | Contenido |
| --- | --- |
| `database/` | CSV locales, excluidos de Git. |
| `scripts/cargar_bd.py` | Carga original desde CSV a PostgreSQL. |
| `scripts/sql/` | Configuración, revisión de calidad, staging y esquema del warehouse. |
| `scripts/preparar_pgagent.ps1` | Comprobación y generación de los comandos del job. |
| `scripts/registrar_pgagent.ps1` | Registro del servicio y del job en pgAgent. |
| `scripts/ejecutar_dbt_pgagent.ps1` | Lanzador del job: dbt, limpieza de dimensiones y logs. |
| `models/sources/` | Declaraciones de las tablas que dbt usa como entrada. |
| `models/staging/` | Modelos de las vistas limpias. |
| `models/intermediate/` | Preparación del contexto promocional de las ventas. |
| `models/dimensions/` | Modelos de las cuatro dimensiones. |
| `models/facts/` | Modelo y pruebas de la tabla de hechos. |
| `macros/` | Lectura entre bases, actualización por diferencias y limpieza de dimensiones. |
| `docs/` | Guías detalladas de cada etapa. |
| `profiles.example.yml` | Plantilla de las dos conexiones dbt. |
| `.env.example` | Plantilla de variables de entorno, sin credenciales reales. |
