-- Materialización de la tabla de hechos de ventas
-- El target warehouse materializa en Data_warehouse.public
-- otorga permisos de selección al rol rol_data_warehouse.
-- Conserva sale_detail_id e inserta nuevas líneas mediante su IDENTITY.
-- Las cuatro llaves son los IDs propios de las dimensiones y no pueden ser nulas.
-- Al crear la tabla agrega las claves foráneas hacia las cuatro dimensiones.

{{ config(materialized='cambios', identity_column='sale_detail_id', schema='public' if target.name == 'warehouse',
    not_null_columns=['dim_product_id', 'dim_household_id', 'dim_time_id', 'dim_promotional_context_id'],
    foreign_keys={'dim_product_id': 'dim_product', 'dim_household_id': 'dim_household',
                  'dim_time_id': 'dim_time', 'dim_promotional_context_id': 'dim_promotional_context'}) }}

-- Cada venta busca el ID propio de cada dimensión con su código original.
-- Si una venta no encuentra su dimensión, la llave queda NULL y la carga falla.
-- El arreglo JSONB compara los siete atributos del contexto con igualdad
-- compatible con hash join. No se guarda este arreglo en la tabla de hechos.
select
    product.dim_product_id,
    household.dim_household_id,
    calendar.dim_time_id,
    context.dim_promotional_context_id,
    sales.store_id as store_id,
    sales.basket_id as basket_id,
    sales.transaction_time_hhmm as transaction_time,
    sales.quantity as quantity,
    sales.sales_value as sales_value,
    sales.retail_discount as retail_discount,
    sales.coupon_discount as coupon_discount,
    sales.coupon_match_discount as manufacturer_coupon_discount
from {{ staging_view('int_sales_promotional_context', alias='sales') }}
left join {{ ref('dim_product') }} product
    on sales.product_id = product.product_id
left join {{ ref('dim_household') }} household
    on sales.household_id = household.household_id
left join {{ ref('dim_time') }} calendar
    on sales.transaction_day = calendar.dataset_day_number
left join {{ ref('dim_promotional_context') }} context
    on jsonb_build_array(
        sales.has_promotion, sales.display_type, sales.mailer_type,
        sales.household_in_active_campaign, sales.active_campaigns_count,
        sales.product_associated_with_coupon, sales.household_with_redemption_today
    ) = context.context_key
