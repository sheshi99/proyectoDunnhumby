# Capa staging

Esta guía cubre los pasos 5 y 8 del [README](../README.md): copiar las tablas
originales a `staging` y crear sobre ellas las vistas limpias con dbt.

En `dunnhumby_etl.staging` hay tres tipos de objetos:

| Objeto | Ejemplo | Quién lo crea |
| --- | --- | --- |
| Copia física de una tabla original, con las columnas del CSV | `staging.transaction_data` | `copiar_tablas_a_staging.sql` |
| Vista limpia preparada | `staging.stg_transaction_data` | Modelos de `models/staging/` |
| Vista intermedia de ventas con contexto promocional | `staging.int_sales_promotional_context` | Modelo de `models/intermediate/` |

Las copias son la entrada de todo el proceso. El
[job automático](job_etl.md) las lee pero no las actualiza: los datos nuevos
deben cargarse en ellas antes de que lleguen al warehouse.

## 1. Copiar las tablas a staging

Requiere las tablas originales en `public` y los roles configurados
([preparación de las bases](instrucciones_de_carga.md)).

Con Query Tool conectado a **`dunnhumby_etl`**, ejecutar completos y en este orden:

1. [copiar_tablas_a_staging.sql](../scripts/sql/staging/copiar_tablas_a_staging.sql):
   copia las ocho tablas de `public` a `staging`.
2. [00_validar_requisitos.sql](../scripts/sql/staging/00_validar_requisitos.sql):
   comprueba las copias y concede a `rol_staging` lectura de las fuentes y
   creación en `staging`. Ese rol debe estar asignado al usuario de dbt.

**Resultado esperado:** ocho tablas físicas en `dunnhumby_etl.staging`.

Detalles de la copia:

- Conserva nombres, tipos y registros, pero no índices, claves, restricciones ni
  valores predeterminados. `public` queda intacto.
- Se ejecuta en una sola transacción. `causal_data` es grande: la copia tarda y
  necesita espacio adicional.
- Si alguna tabla o vista destino ya existe, se detiene sin sobrescribir. Si las
  ocho copias ya están completas, pasar directamente a `00_validar_requisitos.sql`.
- Si hay un error, ejecutar `ROLLBACK` por separado antes de reintentar. No
  borrar objetos con `CASCADE`.

## 2. Crear las vistas limpias

Requiere las conexiones de dbt y `dblink` configuradas
([inicialización de dbt](inicializacion_dbt.md)).

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

**Resultado esperado:** ocho vistas `stg_` y `int_sales_promotional_context` en
`dunnhumby_etl.staging`, con las pruebas en `PASS`.

Las vistas solo renombran columnas, convierten tipos y normalizan textos. Los
descuentos conservan sus signos, no se eliminan filas ni ceros, y los días y
semanas siguen siendo índices del dataset, sin una fecha base inventada.

Para agregar o modificar una vista, ver el
[instructivo de modelos de staging](instructivo_dbt_ETL.md).

Siguiente paso: [crear el modelo estrella](guia_dimensiones_dbt.md#3-ejecución).
