# Funcionamiento del job ETL

Esta guía explica qué hace el job **`Dunnhumby_ETL_cada_2_horas`** y cómo revisar
sus resultados. Para instalarlo o reconfigurarlo, ver la
[configuración de pgAgent](pgagent.md).

## Qué hace

El job actualiza `Data_warehouse` a partir de las copias de staging. Se ejecuta
cada dos horas (minuto 00 de las horas pares) y en cada ejecución:

1. pgAgent llama a [ejecutar_dbt_pgagent.ps1](../scripts/ejecutar_dbt_pgagent.ps1).
2. dbt lee las vistas `stg_` y las compara con las dimensiones y hechos.
3. Inserta, actualiza o elimina solo las diferencias y ejecuta las pruebas.
4. La macro `limpiar_dimensiones` borra dimensiones que ya no se usan y no tienen ventas.

```text
Fuera del job: CSV / public → copias físicas de staging
Job cada dos horas: staging → Data_warehouse
```

El job no modifica staging ni consulta `public`. Para que un dato llegue al
warehouse, primero debe estar cargado en las copias de staging.

No usa tablas auxiliares, triggers ni `TRUNCATE`. Si una ejecución falla, la
siguiente vuelve a comparar todo y aplica lo que falte. Cada modelo guarda su
trabajo por separado: un error posterior no revierte los modelos ya terminados.

## Cómo se conservan los IDs

- `fact_sales.sale_detail_id` se mantiene en las filas sin cambios y en las
  correcciones de medidas. Si cambian hogar, cesta, producto, tienda, día u hora,
  la venta se elimina y se inserta como nueva, porque los CSV no tienen un
  identificador único. Las filas duplicadas se conservan.
- `dim_promotional_context` reutiliza el ID de cada combinación mediante `context_key`.
- Productos y hogares guardan solo sus atributos actuales, sin historial.
- Las dimensiones usadas por alguna venta no se borran, para mantener las FK.

Por eso los modelos nunca reemplazan las tablas y rechazan `--full-refresh`.

## Revisar las ejecuciones

En **pgAdmin → pgAgent Jobs → Dunnhumby_ETL_cada_2_horas → Statistics** se ve
el resultado de cada ejecución. El detalle de dbt queda en
`logs/jobs/*_pgagent.log` y el resumen de la última en
`logs/jobs/ultima_ejecucion.json`.

También se puede consultar desde Query Tool conectado a `postgres`:

```sql
SELECT jobname, jobenabled, jobnextrun, joblastrun
FROM pgagent.pga_job WHERE jobname = 'Dunnhumby_ETL_cada_2_horas';

SELECT l.*
FROM pgagent.pga_joblog l
JOIN pgagent.pga_job j ON j.jobid = l.jlgjobid
WHERE j.jobname = 'Dunnhumby_ETL_cada_2_horas'
ORDER BY l.jlgid DESC
LIMIT 20;
```

## Recomendaciones de operación

- El equipo, PostgreSQL y el servicio `DunnhumbyPgAgent` deben estar encendidos.
  No hace falta tener pgAdmin abierto ni una sesión iniciada.
- Para una ejecución extra, usar **Run now** en pgAdmin.
- No ejecutar dbt manualmente sobre el warehouse mientras el job corre; el
  lanzador impide dos ejecuciones a la vez en el mismo equipo.
- No cargar datos en staging durante una ejecución; esos cambios pueden
  aparecer recién en la siguiente.
