{{ config(materialized='view', grants={'select': ['rol_staging']}) }}

-- Una fila por hogar. Reúne los hogares de ventas, campañas, canjes y demografía
-- y les agrega su perfil. Los hogares sin perfil quedan con
-- 'No demographic profile' (Kimball: los atributos no quedan en NULL).
with households as (
    select household_id from {{ ref('stg_transaction_data') }}
    union select household_id from {{ ref('stg_campaign_table') }}
    union select household_id from {{ ref('stg_coupon_redemptions') }}
    union select household_id from {{ ref('stg_hh_demographic') }}
)

select
    households.household_id::bigint as household_id,
    coalesce(demographics.age_range, 'No demographic profile')::text as age_group,
    -- Códigos según dunnhumby (2014), The Complete Journey User Guide, página 3.
    case
        when demographics.household_id is null then 'No demographic profile'
        when demographics.marital_status_code = 'A' then 'Married'
        when demographics.marital_status_code = 'B' then 'Single'
        when demographics.marital_status_code = 'U' then 'Unknown'
        else 'Unknown code ' || coalesce(demographics.marital_status_code, 'NULL')
    end::text as marital_status,
    coalesce(demographics.income_range, 'No demographic profile')::text as income_range,
    coalesce(demographics.homeownership_status, 'No demographic profile')::text as homeowner_status,
    coalesce(demographics.household_composition, 'No demographic profile')::text as household_composition,
    coalesce(demographics.household_size_category, 'No demographic profile')::text as household_size,
    coalesce(demographics.children_category, 'No demographic profile')::text as kids_category
from households
left join {{ ref('stg_hh_demographic') }} demographics
    on households.household_id = demographics.household_id
