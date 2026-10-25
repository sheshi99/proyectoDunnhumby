{{ config(
    materialized='view', 
    alias='stg_coupon_redemptions', 
    grants={'select': ['rol_staging']}
) }}


select
    household_key::integer as household_id,  -- Convierte a integer y se renombra a household_id para estandarizar identificadores
    "DAY"::integer          as redemption_day, -- Convierte a integer y se aclara que representa el día de la redención
    "COUPON_UPC"::bigint    as coupon_upc,   
    "CAMPAIGN"::integer      as campaign_id    -- Convierte a integer y se renombra a campaign_id para coincidir con stg_campaign_descriptions
from {{ source('dunnhumby_raw', 'coupon_redempt') }}


