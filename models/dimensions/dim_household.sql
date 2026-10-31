{{ config(materialized='cambios', unique_key='household_id', schema='public' if target.name == 'warehouse') }}

-- Una fila por hogar conocido, aunque no tenga perfil demográfico.
-- Consulta los hogares actuales y compara sus atributos con la dimensión.
with households as (
    select household_id from {{ staging_view('stg_transaction_data') }}
    union select household_id from {{ staging_view('stg_campaign_table') }}
    union select household_id from {{ staging_view('stg_coupon_redemptions') }}
    union select household_id from {{ staging_view('stg_hh_demographic') }}
)

select
    households.household_id::bigint as household_id,
    demographics.age_range::text as age_group,
    demographics.marital_status_code::text as marital_status,
    demographics.income_range::text as income_range,
    demographics.homeownership_status::text as homeowner_status,
    demographics.household_composition::text as household_composition,
    demographics.household_size_category::text as household_size,
    demographics.children_category::text as kids_category
from households
left join {{ staging_view('stg_hh_demographic', alias='demographics') }}
    on households.household_id = demographics.household_id
