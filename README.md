# Proyecto Dunnhumby

## Resumen

Proyecto ETL para cargar el conjunto de datos Dunnhumby en PostgreSQL, revisar su calidad y prepararlo para transformaciones con dbt. El flujo recomendado está abajo; las guías enlazadas contienen los detalles y comandos de cada etapa.

## Flujo de trabajo

1. **Preparar el entorno y cargar los datos.** Sigue [`docs/instrucciones_de_carga.md`](docs/instrucciones_de_carga.md). La carga se realiza con `scripts/cargar_bd.py` y los CSV locales de `database/`.
2. **Revisar la calidad.** En la base `dunnhumby_etl`, ejecuta las consultas de `scripts/sql/RevisionCalidad/`, una por cada tabla. Esta revisión de las tablas originales en `public` permite inspeccionar anomalías antes del modelado.
3. **Configurar esquemas y permisos.** Ejecuta `scripts/sql/Configuraciones/esquema_roles_permisos.sql` en `dunnhumby_etl` con un usuario administrador.
4. **Crear y validar staging.** Ejecuta en orden `scripts/sql/staging/01_crear_staging.sql` y `scripts/sql/staging/02_validar_staging.sql`. Consulta [`docs/capa_staging.md`](docs/capa_staging.md) para conocer el diseño y las comprobaciones.
5. **Configurar dbt cuando se vaya a trabajar en modelos.** Sigue [`docs/inicializacion_dbt.md`](docs/inicializacion_dbt.md).

## Carpetas principales

- `database/`: CSV locales del dataset; no se incluyen en Git.
- `scripts/`: carga de datos y SQL para configuración, revisión de calidad y staging.
- `models/`: fuentes de datos para dbt.
- `docs/`: guías detalladas del flujo y de staging.

La carga puede reemplazar las tablas existentes. Revisa la guía de carga antes de ejecutarla sobre una base que ya contenga datos.
