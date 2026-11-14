# Carga inicial de CSV con dbt y COPY

## Qué hace cada parte

Los ocho CSV de Dunnhumby están en la carpeta `database/` del proyecto. La carga
se hace con el mismo `dbt build` de siempre, agregando `--vars "{cargar_csv: true}"`.
PostgreSQL lee los archivos con `COPY` y los carga en `dunnhumby_etl.public`;
después los modelos construyen staging, las dimensiones y `fact_sales`.

```text
database/*.csv → hook cargar_csv_al_iniciar → macro cargar_csv (PostgreSQL COPY)
    → dunnhumby_etl.public → sincronización → staging → dimensiones y fact_sales
```

| Archivo | Función |
| --- | --- |
| [macros/cargar_csv_al_iniciar.sql](../macros/cargar_csv_al_iniciar.sql) | Hook `on-run-start` de [dbt_project.yml](../dbt_project.yml). Solo actúa con `dbt build --target dev --vars "{cargar_csv: true}"`. Busca sola la carpeta `database/` del proyecto. |
| [macros/cargar_csv.sql](../macros/cargar_csv.sql) | Valida los encabezados y carga las ocho tablas con `COPY`, en una sola transacción. |

## 1. Requisito: que PostgreSQL pueda leer `database/` (una vez por equipo)

`COPY` lo ejecuta el **servicio de PostgreSQL**, no nuestro usuario de Windows.
Si ese servicio no tiene permiso sobre la carpeta, el build se detiene con
`PostgreSQL no puede leer ...` y muestra el comando exacto para corregirlo. Es un
permiso de Windows; dbt no puede darlo. Desde la raíz del proyecto, en PowerShell:

```powershell
icacls database /grant "*S-1-5-20:(OI)(CI)RX"
```

`S-1-5-20` es `NetworkService`, la cuenta con la que se instala PostgreSQL en
Windows. Solo concede lectura sobre `database/`.

Otros requisitos:

- El usuario de `.env` debe ser superusuario de PostgreSQL (como `postgres`),
  porque `COPY` desde archivos o programas lo exige.
- Nombres esperados: `campaign_desc.csv`, `campaign_table.csv`, `causal_data.csv`,
  `coupon.csv`, `coupon_redempt.csv`, `hh_demographic.csv`, `product.csv` y
  `transaction_data.csv`, con encabezados originales, coma y UTF-8.

**Rutas con tildes.** PostgreSQL en Windows no abre rutas con tildes (por ejemplo
"Minería de datos"). En ese caso la macro no usa `COPY FROM 'archivo'` sino
`COPY FROM PROGRAM`, con un comando de PowerShell que lee el archivo y se lo pasa
a PostgreSQL. Cada letra con tilde va como código (`í` = `[char]237`). Se hace
automáticamente y el resultado es idéntico.

## 2. Cargar los CSV

Con `venv` activado y desde la raíz del proyecto, con las ocho tablas de `public`
todavía sin crear:

```powershell
python -m dotenv -f .env run -- dbt build --profiles-dir . --target dev --select path:models/sincronizacion path:models/staging path:models/intermediate --vars "{cargar_csv: true}"

python -m dotenv -f .env run -- dbt build --profiles-dir . --target warehouse --select path:models/dimensions path:models/facts
```

El primer comando carga los CSV en `public` (unos 2 minutos) y luego construye
staging. El segundo construye las dimensiones y `fact_sales`. Ejecutar el segundo
solo si el primero termina bien.

En las ejecuciones siguientes, **quitar** `--vars "{cargar_csv: true}"`.

## 3. Protecciones

- **No reemplaza tablas existentes.** Si alguna de las ocho tablas ya está en
  `public`, se detiene con `... ya existe` y no cambia nada.
- **Todo o nada.** Las ocho tablas se cargan en una transacción.
- **Solo `dev`.** Con `--target warehouse` la carga se niega.
- **No afecta al job diario.** Sin `cargar_csv: true` el hook no hace nada.
- No permite dos cargas a la vez.

## 4. Cargar sin construir modelos (`run-operation`)

En una instalación nueva, donde todavía no existen los roles ni `dblink`, cargar
solo `public` y seguir después con las guías:

```powershell
python -m dotenv -f .env run -- dbt run-operation cargar_csv --profiles-dir . --target dev
```

Variantes, agregando `--args`:

| `--args` | Efecto |
| --- | --- |
| `"{solo_validar: true}"` | Comprueba los ocho archivos; no crea ni carga nada. |
| `"{esquema: carga_csv_prueba}"` | Carga en un esquema de prueba, sin tocar `public`. |
| `"{reemplazar: true}"` | Sustituye a propósito el contenido de `public` (`TRUNCATE` + `COPY`). No usarlo mientras corre el job. |

Sin `directorio_csv`, la macro usa la carpeta `database/` del proyecto.

## 5. Prueba realizada (13-nov-2026)

- Validación y carga completa leyendo `database/` con la ruta con tildes
  (`COPY FROM PROGRAM`), en `carga_csv_prueba`: 118 segundos.
- Comparación con `public`: siete tablas idénticas fila por fila (`EXCEPT ALL` en
  ambos sentidos, 0 diferencias); `causal_data` con el mismo conteo y la misma
  distribución de `display`/`mailer`. El esquema de prueba se eliminó.
- `dbt build` con `cargar_csv: true` y tablas existentes: se detiene sin cambios.
- `dbt build` sin la variable: termina normal; el hook no hace nada.

| Tabla | Registros |
| --- | ---: |
| `transaction_data` | 2 595 732 |
| `causal_data` | 36 786 524 |
| `product` | 92 353 |
| `coupon` | 124 548 |
| `campaign_table` | 7 208 |
| `coupon_redempt` | 2 318 |
| `hh_demographic` | 801 |
| `campaign_desc` | 30 |

## Cómo volver atrás

Para quitar el permiso concedido sobre `database/`:

```powershell
icacls database /remove "*S-1-5-20"
```
