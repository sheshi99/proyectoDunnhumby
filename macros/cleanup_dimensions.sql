-- Elimina productos y hogares sin ventas que ya no aparecen en staging, y días sin ventas.
-- El job la ejecuta después de dbt build; los contextos promocionales no se borran.

{% macro limpiar_dimensiones() %}
  {% if target.name != 'warehouse' %}{{ exceptions.raise_compiler_error('Usar target warehouse') }}{% endif %}
  {% call statement('cleanup', auto_begin=True) %}
    delete from public.dim_product t
    where not exists(select 1 from public.fact_sales f where f.dim_product_id=t.dim_product_id)
      and t.product_id not in (select * from {{ remote_query('select "PRODUCT_ID" from staging.product', 'id bigint') }});
    delete from public.dim_household t
    where not exists(select 1 from public.fact_sales f where f.dim_household_id=t.dim_household_id)
      and t.household_id not in (select * from {{ remote_query('select household_id from staging.stg_hh_demographic union select household_id from staging.stg_campaign_table union select household_id from staging.stg_coupon_redemptions union select household_id from staging.stg_transaction_data', 'id bigint') }});
    delete from public.dim_time t
    where not exists(select 1 from public.fact_sales f where f.dim_time_id=t.dim_time_id);
  {% endcall %}
  {% do adapter.commit() %}
{% endmacro %}
