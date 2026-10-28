# Staging: tablas originales y vistas de dbt

## Estructura acordada

- staging.transaction_data: tabla original con columnas del CSV.
- staging.stg_transaction_data: vista preparada por dbt.
- staging.causal_data: tabla original con columnas del CSV.
- staging.stg_causal_data: vista preparada por dbt.

Las ocho fuentes se copian de public a staging con copiar_tablas_a_staging.sql.
Los ocho modelos de vistas están implementados en `models/staging/`.
También existe la vista `int_sales_promotional_context`, construida por el modelo
de `models/intermediate/`. Las dimensiones y hechos se crean después en
`Data_warehouse.public`, con una conexión diferente.

## Orden de ejecucion

1. Crear la base dunnhumby_etl y configurar roles y permisos.
2. Si faltan las tablas de public, ejecutar python scripts/cargar_bd.py.
3. Ejecutar completo copiar_tablas_a_staging.sql en pgAdmin.
4. Ejecutar completo 00_validar_requisitos.sql en pgAdmin.
5. Configurar `.env` y `profiles.yml` según la [guía de inicialización](inicializacion_dbt.md).
6. Ejecutar desde la raíz del proyecto:

   ```powershell
   python -m dotenv -f .env run -- dbt run --profiles-dir . --target dev --select path:models/staging path:models/intermediate
   ```

7. Ejecutar las pruebas de staging:

   ```powershell
   python -m dotenv -f .env run -- dbt test --profiles-dir . --target dev --select path:models/staging
   ```

8. Ejecutar `03_validar_staging.sql` en pgAdmin conectado a `dunnhumby_etl`.
   Compara específicamente las vistas de transacciones y datos causales con sus
   tablas de trabajo y evalúa sus conversiones.

Las vistas preparadas se crean exclusivamente con los modelos de dbt.
Los descuentos conservan sus signos, los ceros y filas no se eliminan y
los dias y semanas siguen siendo indices sin una fecha base inventada.

## Copia y objetos existentes

copiar_tablas_a_staging.sql conserva nombres, tipos y registros de public. No copia
indices, claves, restricciones ni valores predeterminados. Necesita SELECT en
public y permiso para crear tablas en staging. Todo se ejecuta en una sola
transaccion con una misma instantanea de los datos. causal_data es grande:
la copia requiere espacio adicional y puede tardar.

El script comprueba las ocho fuentes y los ocho destinos antes de copiar.
Si cualquier destino ya existe (tabla o vista), se detiene sin sobrescribirlo.
No es un script de actualizacion periodica. Si ya existen copias completas,
no repetir la copia; continuar con los requisitos. Si solo existen algunos
objetos, revisar como completar la migracion antes de continuar.
Si hay un error, ejecutar ROLLBACK por separado antes de reintentar.

Los datos de public permanecen intactos. Las copias de staging no se actualizan
automaticamente cuando cambia public; una recarga necesita un proceso aparte.
No borrar objetos con CASCADE. Los cambios anteriores de dbt pueden haber
creado vistas sin prefijo; revisarlas antes de copiar sobre esos nombres.
El usuario de dbt necesita SELECT en las fuentes y CREATE en staging;
00_validar_requisitos.sql concede esos permisos a rol_staging, que debe estar
asignado al usuario de dbt.
