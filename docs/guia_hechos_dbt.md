# Guía del equipo: tabla de hechos en dbt

`models/facts/fact_sales.sql` crea `data_warehouse.fact_sales`, siguiendo los nombres de `scripts/sql/data_warehouse/star_schema.sql`. Una fila representa una línea original de compra, no una cesta completa. No se agrupan ventas ni se eliminan líneas repetidas.

## Cómo se construye

1. Lee `int_sales_promotional_context`, que conserva las transacciones y agrega los indicadores promocionales.
2. Busca en `dim_promotional_context` la combinación de los siete atributos, comparando también los valores NULL. Recupera su `promotional_context_id`.
3. Conserva producto, hogar, tienda, cesta, hora, cantidad e importes. El día se guarda como `time_id`. PostgreSQL agrega `sale_detail_id` como clave primaria IDENTITY.

Las claves `product_id`, `household_id`, `time_id`, `campaign_id` y `promotional_context_id` relacionan los hechos con sus dimensiones mediante restricciones `FOREIGN KEY` físicas. `store_id` no tiene relación porque el esquema todavía no incluye una dimensión de tienda. Los `ref()` y las dependencias declaradas en el modelo ordenan la construcción de dimensiones antes que los hechos.

`campaign_id` se guarda como NULL: tener una campaña asignada vigente no demuestra que esa campaña originó la compra, aunque sea la única. No se elige una campaña al azar.

Se conservan ceros, NULL y signos de los descuentos. El nombre `manufacturer_coupon_discount` viene del diagrama y recibe directamente `coupon_match_discount` (COUPON_MATCH_DISC); no se calcula otro descuento. Los importes se tipan como numeric(18,4), siguiendo el esquema. La prueba de conservación detectará si esa precisión modifica algún valor original.

## Ejecutar y comprobar

Desde la raíz del proyecto, con las fuentes y la conexión configuradas:

```powershell
python -m dotenv -f .env run -- dbt build --select +fact_sales --profiles-dir .
```

El `+` incluye las vistas de entrada y las cinco dimensiones. `build` construye los modelos y ejecuta las pruebas. Si se reconstruye el contexto, hay que reconstruir también los hechos porque sus claves IDENTITY pueden cambiar. Esta carga es completa; no es incremental.

Las pruebas verifican claves obligatorias, unicidad del identificador, relaciones con las dimensiones y ausencia de contextos repetidos. Además, comparan las líneas de hechos con staging mediante `EXCEPT ALL`: deben coincidir los valores y la cantidad de apariciones de cada línea. Así se detectan pérdidas y multiplicaciones de transacciones, incluso cuando las sumas coincidan.

Las relaciones se validan con pruebas dbt y restricciones `FOREIGN KEY` físicas en PostgreSQL. La clave primaria y la obligatoriedad del contexto también se crean en PostgreSQL. Reconstruir las dimensiones antes que los hechos para que las restricciones puedan crearse correctamente. Usar `dbt build` para construir y verificar, en lugar de limitarse a `dbt run`.

Para consultar una muestra en pgAdmin:

```sql
select * from data_warehouse.fact_sales limit 10;
```
