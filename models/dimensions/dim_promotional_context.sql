{{ config(materialized='cambios', unique_key='context_key', identity_column='promotional_context_id', schema='public' if target.name == 'warehouse') }}

-- Las combinaciones nuevas reciben IDENTITY; las existentes conservan su ID.
with contexts as (
    select distinct
        has_promotion,
        display_type,
        mailer_type,
        household_in_active_campaign,
        active_campaigns_count,
        product_associated_with_coupon,
        household_with_redemption_today
    from {{ staging_view('int_sales_promotional_context') }}
)
select
    jsonb_build_array(has_promotion, display_type, mailer_type,
        household_in_active_campaign, active_campaigns_count,
        product_associated_with_coupon, household_with_redemption_today) as context_key,
    contexts.*
from contexts
