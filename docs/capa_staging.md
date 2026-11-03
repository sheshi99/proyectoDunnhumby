# Capa staging

Esta guía cubre los pasos 5 y 8 del [README](../README.md): copiar las tablas
originales a `staging` y crear sobre ellas las vistas limpias con dbt.

En `dunnhumby_etl.staging` hay tres tipos de objetos:

| Objeto | Ejemplo | Quién lo crea |
| --- | --- | --- |
| Copia física de una tabla original, con las columnas del CSV | `staging.transaction_data` | Modelos de `models/sincronizacion/` |
| Vista limpia preparada | `staging.stg_transaction_data` | Modelos de `models/staging/` |
| Vista intermedia que prepara una dimensión o los hechos | `staging.int_household`, `staging.int_time`, `staging.int_sales_promotional_context` | Modelos de `models/intermediate/` |

Las copias son la entrada de todo el proceso. El [job automático](job_etl.md)
las sincroniza con `public` en cada ejecución, antes de actualizar el warehouse:
los datos nuevos, modificados o eliminados se cargan en `public` y el job los
lleva a staging.

## 1. Copiar las tablas a staging

Requiere las tablas originales en `public`, los roles configurados
([preparación de las bases](instrucciones_de_carga.md)) y las conexiones de dbt
([inicialización de dbt](inicializacion_dbt.md)).

1. Copiar las ocho tablas con dbt:

   ```powershell
   python -m dotenv -f .env run -- dbt run `
       --profiles-dir . `
       --target dev `
       --select path:models/sincronizacion
   ```

2. Con Query Tool conectado a **`dunnhumby_etl`**, ejecutar completo
   [00_validar_requisitos.sql](../scripts/sql/staging/00_validar_requisitos.sql):
   comprueba las copias y concede a `rol_staging` lectura de las fuentes y
   creación en `staging`. Ese rol debe estar asignado al usuario de dbt.

**Resultado esperado:** ocho tablas físicas en `dunnhumby_etl.staging`.

Cómo funciona la copia ([sincronizar_origen.sql](../macros/sincronizar_origen.sql)):

- La primera vez crea cada tabla con todas las filas de `public`. Conserva
  nombres, tipos y registros, pero no índices ni restricciones. `public` queda
  intacto.
- Las siguientes veces solo aplica las diferencias: inserta las filas nuevas y
  borra las que ya no están en `public`. Una fila modificada se borra en su
  versión anterior y se inserta en la nueva. El log indica cuántas filas se
  borraron e insertaron en cada tabla.
- Las tablas no tienen clave única y hay filas repetidas legítimas, por eso se
  compara cuántas veces aparece cada fila: si `public` tiene una fila tres veces,
  staging también.
- Cada tabla se actualiza en una sola transacción. `causal_data` es grande: su
  comparación tarda unos 3 minutos.
- Si las columnas de una tabla de `public` cambian, la ejecución se detiene sin
  modificar la copia.

## 2. Crear las vistas limpias

1. Crear las ocho vistas `stg_` y la vista intermedia:

   ```powershell
   python -m dotenv -f .env run -- dbt run `
       --profiles-dir . `
       --target dev `
       --select path:models/staging path:models/intermediate
   ```

2. Ejecutar las pruebas de las vistas:

   ```powershell
   python -m dotenv -f .env run -- dbt test `
       --profiles-dir . `
       --target dev `
       --select path:models/staging
   ```

3. Como comprobación adicional, ejecutar
   [03_validar_staging.sql](../scripts/sql/staging/03_validar_staging.sql) en
   Query Tool conectado a `dunnhumby_etl`. Compara las vistas de transacciones y
   datos causales con sus copias y revisa las conversiones de tipos.

**Resultado esperado:** ocho vistas `stg_` y las tres vistas `int_` en
`dunnhumby_etl.staging`, con las pruebas en `PASS`.

Las vistas solo renombran columnas, convierten tipos y normalizan textos. Los
descuentos conservan sus signos, no se eliminan filas ni ceros, y los días y
semanas se conservan como índices del dataset. `stg_transaction_data` agrega
`transaction_date`, calculada desde la fecha base supuesta `2004-01-01`.
Los textos vacíos de producto se reemplazan por `'not available'`; ver
[tratamiento de nulos](tratamiento_nulos.md).

Para agregar o modificar una vista, ver el
[instructivo de modelos de staging](instructivo_dbt_ETL.md).

Siguiente paso: [crear el modelo estrella](guia_dimensiones_dbt.md#3-ejecución).
