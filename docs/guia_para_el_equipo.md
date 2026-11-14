# Prueba de la nueva carga de datos con dbt

Compañeras, cambiamos la carga inicial de los CSV para ejecutarla desde dbt.
Como ya tenemos el proyecto configurado, vamos a probarla eliminando las tablas
originales de `public` y volviéndolas a crear con el nuevo proceso.

## 1. Actualizar el proyecto

Cuando los cambios estén publicados, actualizar el repositorio:

```powershell
git pull
```

Conservar el entorno `venv`, `.env`, `profiles.yml` y los ocho CSV originales.
No es necesario reinstalar el proyecto ni crear las bases otra vez.

## 2. Preparar el acceso a la carpeta `database/`

Los CSV se leen directamente de la carpeta `database/` que ya tenemos en el
proyecto; dbt la encuentra sola. No hay que copiarlos ni escribir rutas en `.env`.

PostgreSQL necesita permiso de Windows para leer esa carpeta. Desde la raíz del
proyecto, en PowerShell (una sola vez):

```powershell
icacls database /grant "*S-1-5-20:(OI)(CI)RX"
```

Después, con `venv` activado, comprobar los ocho archivos **sin cargar ni borrar
datos**:

```powershell
python -m dotenv -f .env run -- dbt run-operation cargar_csv --profiles-dir . --target dev --args "{solo_validar: true}"
```

Debe terminar con ocho líneas `CSV validado` y `Validación terminada`. Si falla,
**no continuar** con el paso 3: compartir el mensaje. Si el proyecto está en
OneDrive, los CSV deben estar descargados en el equipo. Más detalle en
[carga_csv_dbt.md](carga_csv_dbt.md).

## 3. Borrar únicamente las tablas originales de public

En pgAdmin, abrir Query Tool conectado a **`dunnhumby_etl`**, no a
`Data_warehouse`. Ejecutar el bloque completo:

```sql
BEGIN;

DO $$
BEGIN
    IF current_database() <> 'dunnhumby_etl' THEN
        RAISE EXCEPTION 'Conectarse a dunnhumby_etl antes de borrar las tablas originales';
    END IF;
END $$;

DROP TABLE IF EXISTS
    public.campaign_desc,
    public.campaign_table,
    public.causal_data,
    public.coupon,
    public.coupon_redempt,
    public.hh_demographic,
    public.product,
    public.transaction_data;

COMMIT;
```

Esto elimina las ocho tablas originales y su contenido para probar la carga
desde los CSV. **No borrar las bases, el esquema `public`, staging, sus vistas,
las dimensiones ni `fact_sales`.** Para esta prueba solo necesitamos retirar
las tablas de origen. Realizarla sin una ejecución del job en curso.

El bloque no utiliza `CASCADE`. Si aparece un error por dependencias, ejecutar
`ROLLBACK;` y compartir el mensaje antes de continuar.

## 4. Cargar los originales y construir staging

Desde la raíz del proyecto, con `venv` activado:

```powershell
python -m dotenv -f .env run -- dbt build `
    --profiles-dir . `
    --target dev `
    --select path:models/sincronizacion path:models/staging path:models/intermediate `
    --vars "{cargar_csv: true}"
```

Este comando realiza lo siguiente, en orden:

1. Localiza la carpeta `database/` del proyecto.
2. Ejecuta la macro que carga los ocho CSV en `dunnhumby_etl.public`.
3. Sincroniza las copias de staging y construye las vistas.
4. Ejecuta las pruebas de los modelos seleccionados.

Las tablas originales deben volver a aparecer en `public`. La limpieza de datos
se realiza después en las vistas, conservando los datos originales en `public`.

La carga no reemplaza tablas existentes. Por eso las eliminamos antes de esta
prueba. Si el comando falla, no ejecutar inmediatamente el siguiente paso:
compartir el error y revisar si las tablas originales ya quedaron cargadas.
La carga de CSV y los modelos posteriores no forman una única transacción.

## 5. Actualizar el modelo estrella

Cuando el primer build termine correctamente:

```powershell
python -m dotenv -f .env run -- dbt build `
    --profiles-dir . `
    --target warehouse `
    --select path:models/dimensions path:models/facts
```

Este comando actualiza las cuatro dimensiones y `fact_sales` en
`Data_warehouse.public` y ejecuta sus pruebas. Como conservamos esas tablas,
aplica las diferencias que encuentre; no es necesario reconstruirlas desde cero
para comprobar la nueva carga inicial.

## 6. Comprobar el resultado

En pgAdmin, conectado a **`dunnhumby_etl`**:

```sql
SELECT count(*) AS transacciones_originales FROM public.transaction_data;
SELECT count(*) AS registros_causales FROM public.causal_data;
```

Conectado a **`Data_warehouse`**:

```sql
SELECT count(*) AS lineas_de_venta FROM public.fact_sales;
```

Para los CSV que utilizamos en el proyecto, los valores esperados son:

| Comprobación | Registros |
| --- | ---: |
| `public.transaction_data` en `dunnhumby_etl` | 2 595 732 |
| `public.causal_data` en `dunnhumby_etl` | 36 786 524 |
| `public.fact_sales` en `Data_warehouse` | 2 595 732 |

Ambos builds deben terminar sin errores. Compartir sus resúmenes y los conteos
con el equipo para dejar evidencia de la prueba. Los conteos son una comprobación
inicial; no demuestran por sí solos igualdad de todos los valores.

## 7. Después de esta prueba

Para las siguientes ejecuciones, usar el build de `dev` **sin**
`--vars "{cargar_csv: true}"` y luego el de `warehouse`.

No hay que borrar ni volver a importar los originales cada vez que trabajamos.
La eliminación indicada arriba corresponde únicamente a esta prueba de carga
desde cero. El job diario continúa procesando los cambios de `public` como antes.

## Nuevo flujo y motivo del cambio

Antes, `cargar_bd.py` leía los CSV con pandas y los cargaba en PostgreSQL.
Después usábamos dbt para las transformaciones y el modelo estrella.

Ahora el flujo es:

```text
dbt build --target dev + cargar_csv: true
    → macro cargar_csv
    → PostgreSQL COPY lee los CSV
    → originales en dunnhumby_etl.public
    → copias y vistas de staging

dbt build --target warehouse
    → dimensiones y fact_sales en Data_warehouse.public
    → consultas y tablas dinámicas de Excel
```

La carga inicial se activa mediante un hook, es decir, un paso previo al build.
Solo se solicita cuando agregamos `cargar_csv: true` al build de `dev`.

Hicimos el cambio para dirigir también la importación desde dbt y utilizar
`COPY` de PostgreSQL para la carga masiva de los archivos. No usamos seeds para
importar los millones de registros ni necesitamos el antiguo cargador de pandas.
Seguimos utilizando los comandos con `python -m dotenv` que ya conocemos.

`venv` se conserva porque dbt Core está desarrollado en Python. El cambio no
modifica las dimensiones, las medidas ni la granularidad: `fact_sales` sigue
representando una línea original de compra por fila.

Primero se cargan los datos originales y después se transforman dentro de
PostgreSQL; esa parte mantiene un enfoque ELT. Lo que cambia es que la carga
inicial también queda dirigida por dbt.

La macro de carga ya se probó leyendo directamente `database/`: los ocho archivos
cargados en un esquema de prueba coincidieron con las tablas de `public`. Esta prueba
del equipo permitirá comprobar el flujo completo invocado desde `dbt build`
y el acceso a los CSV en cada computadora.
