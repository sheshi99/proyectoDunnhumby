{{ config(materialized='cambios', identity_column='dim_promotional_context_id', schema='public' if target.name == 'warehouse',
    unique_key=['has_promotion', 'display_type', 'mailer_type', 'household_in_active_campaign',
        'active_campaigns_count', 'product_associated_with_coupon', 'household_with_redemption_today']) }}

-- Las combinaciones nuevas reciben IDENTITY; las existentes conservan su ID.
-- Cada combinación se reconoce por sus siete atributos, que nunca son NULL.
select distinct
    has_promotion,
    display_type,
    mailer_type,
    household_in_active_campaign,
    active_campaigns_count,
    product_associated_with_coupon,
    household_with_redemption_today
from {{ staging_view('int_sales_promotional_context') }}
