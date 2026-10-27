{{ config(materialized='view', grants={'select': ['rol_staging']}) }}

-- Una fila por línea original. Las relaciones múltiples se resumen antes
-- de unirlas con ventas. No atribuye un cupón ni una campaña a una línea.
with causal_rows as (
    select
        product_id,
        store_id,
        week_number,
        display,
        mailer,
        display in ('1', '2', '3', '4', '5', '6', '7', '9', 'A')
            or mailer in ('A', 'C', 'D', 'F', 'H', 'J', 'L', 'P', 'X', 'Z')
            as positive_evidence,
        display = '0' and mailer = '0' as explicit_absence
    from {{ ref('stg_causal_data') }}
), causal_by_key as (
    select
        product_id,
        store_id,
        week_number,
        case
            when bool_or(positive_evidence) then true
            when bool_and(coalesce(explicit_absence, false)) then false
            else null::boolean
        end as has_promotion,
        -- Listas de códigos de cada canal, no combinaciones entre canales.
        -- Mantener NULL como dato desconocido si apareciera en la fuente.
        array_to_json(array_agg(distinct display order by display))::text as display_type,
        array_to_json(array_agg(distinct mailer order by mailer))::text as mailer_type
    from causal_rows
    group by product_id, store_id, week_number
), observed_days as (
    select distinct transaction_day from {{ ref('stg_transaction_data') }}
), campaign_days as (
    -- Vigencia inclusiva, expresada en días del dataset; sin fechas inventadas.
    select distinct campaigns.campaign_id, days.transaction_day
    from {{ ref('stg_campaign_descriptions') }} campaigns
    join observed_days days
        on days.transaction_day between campaigns.start_day and campaigns.end_day
), household_campaigns as (
    select distinct household_id, campaign_id
    from {{ ref('stg_campaign_table') }}
), household_day as (
    select assignments.household_id, days.transaction_day,
        count(distinct days.campaign_id)::integer as active_campaigns_count
    from household_campaigns assignments
    join campaign_days days on assignments.campaign_id = days.campaign_id
    group by assignments.household_id, days.transaction_day
), coupon_products as (
    -- Una asociación producto-campaña basta para comprobar disponibilidad.
    select distinct product_id, campaign_id from {{ ref('stg_coupon') }}
), coupon_product_day as (
    select distinct coupons.product_id, days.transaction_day
    from coupon_products coupons
    join campaign_days days on coupons.campaign_id = days.campaign_id
), redemption_day as (
    select distinct household_id, redemption_day
    from {{ ref('stg_coupon_redemptions') }}
)
select
    sales.household_id,
    sales.basket_id,
    sales.transaction_day,
    sales.product_id,
    sales.quantity,
    sales.sales_value,
    sales.store_id,
    sales.retail_discount,
    sales.transaction_time_hhmm,
    sales.transaction_week,
    sales.coupon_discount,
    sales.coupon_match_discount,
    causal.has_promotion,
    causal.display_type,
    causal.mailer_type,
    coalesce(campaigns.active_campaigns_count, 0) > 0 as household_in_active_campaign,
    coalesce(campaigns.active_campaigns_count, 0) as active_campaigns_count,
    coupons.product_id is not null as product_associated_with_coupon,
    redemptions.household_id is not null as household_with_redemption_today
from {{ ref('stg_transaction_data') }} sales
left join causal_by_key causal
    on sales.product_id = causal.product_id
   and sales.store_id = causal.store_id
   and sales.transaction_week = causal.week_number
left join household_day campaigns
    on sales.household_id = campaigns.household_id
   and sales.transaction_day = campaigns.transaction_day
left join coupon_product_day coupons
    on sales.product_id = coupons.product_id
   and sales.transaction_day = coupons.transaction_day
left join redemption_day redemptions
    on sales.household_id = redemptions.household_id
   and sales.transaction_day = redemptions.redemption_day
