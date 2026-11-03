-- Elimina de las dimensiones las filas que quedaron sin uso:
--   productos y hogares sin ventas que ya no están en las vistas de staging,
--   días sin ventas y contextos promocionales sin ventas.
-- El job la ejecuta después de dbt build.
-- Las listas de productos y hogares se leen de las mismas vistas que cargan
-- dim_product (stg_product) y dim_household (int_household), para no repetir lógica.

{% macro limpiar_dimensiones() %}
  {% if target.name != 'warehouse' %}{{ exceptions.raise_compiler_error('Usar target warehouse') }}{% endif %}
  {% call statement('cleanup', auto_begin=True) %}
    delete from public.dim_product t
    where not exists(select 1 from public.fact_sales f where f.dim_product_id=t.dim_product_id)
      and t.product_id not in (select * from {{ remote_query('select product_id from staging.stg_product', 'id bigint') }});
    delete from public.dim_household t
    where not exists(select 1 from public.fact_sales f where f.dim_household_id=t.dim_household_id)
      and t.household_id not in (select * from {{ remote_query('select household_id from staging.int_household', 'id bigint') }});
    delete from public.dim_time t
    where not exists(select 1 from public.fact_sales f where f.dim_time_id=t.dim_time_id);
    -- Una combinación sin ventas no la usa ninguna fila de fact_sales.
    -- Si vuelve a aparecer, la carga la inserta de nuevo con otro ID.
    delete from public.dim_promotional_context t
    where not exists(select 1 from public.fact_sales f where f.dim_promotional_context_id=t.dim_promotional_context_id);
  {% endcall %}
  {% do adapter.commit() %}
{% endmacro %}
