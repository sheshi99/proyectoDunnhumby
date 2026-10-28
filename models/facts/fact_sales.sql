-- Materialización de la tabla de hechos de ventas
-- El target warehouse materializa en Data_warehouse.public
-- otorga permisos de selección al rol rol_data_warehouse.
-- Coloca sale_detail_id primero y activa su identidad al finalizar la carga.
-- Asegura que la columna promotional_context_id no sea nula.
-- Agrega claves foráneas hacia las cuatro dimensiones.
-- Dependencias: dim_product, dim_household, dim_time,
-- dim_promotional_context

{{ config(
    materialized='table',
    schema='public' if target.name == 'warehouse' else 'data_warehouse',
    grants={'select': ['rol_data_warehouse']},
    post_hook=[
        "{{ initialize_identity(this, 'sale_detail_id') }}",
        'alter table {{ this }} add primary key (sale_detail_id)',
        'alter table {{ this }} alter column promotional_context_id set not null',
        "alter table {{ this }} add constraint fk_sales_product foreign key (product_id) references {{ ref('dim_product') }} (product_id)",
        "alter table {{ this }} add constraint fk_sales_household foreign key (household_id) references {{ ref('dim_household') }} (household_id)",
        "alter table {{ this }} add constraint fk_sales_time foreign key (time_id) references {{ ref('dim_time') }} (time_id)",
        "alter table {{ this }} add constraint fk_sales_promotional_context foreign key (promotional_context_id) references {{ ref('dim_promotional_context') }} (promotional_context_id)"
    ]
) }}

-- Una fila por línea original, sin DISTINCT ni agregación de ventas.
-- El arreglo JSONB compara los siete atributos, incluidos NULL, con igualdad
-- compatible con hash join. No se guarda este arreglo en la tabla de hechos.
select
    row_number() over () as sale_detail_id,
    sales.product_id as product_id,
    sales.household_id as household_id,
    sales.transaction_day as time_id,
    context.promotional_context_id,
    sales.store_id as store_id,
    sales.basket_id as basket_id,
    sales.transaction_time_hhmm as transaction_time,
    sales.quantity as quantity,
    sales.sales_value as sales_value,
    sales.retail_discount as retail_discount,
    sales.coupon_discount as coupon_discount,
    sales.coupon_match_discount as manufacturer_coupon_discount
from {{ staging_view('int_sales_promotional_context', alias='sales') }}
left join {{ ref('dim_promotional_context') }} context
    on jsonb_build_array(
        sales.has_promotion, sales.display_type, sales.mailer_type,
        sales.household_in_active_campaign, sales.active_campaigns_count,
        sales.product_associated_with_coupon, sales.household_with_redemption_today
    ) = jsonb_build_array(
        context.has_promotion, context.display_type, context.mailer_type,
        context.household_in_active_campaign, context.active_campaigns_count,
        context.product_associated_with_coupon, context.household_with_redemption_today
    )
