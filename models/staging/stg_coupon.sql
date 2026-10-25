{{ config(
    materialized='view',
    alias='stg_coupon',
    grants={'select': ['rol_staging']}
) }}


select distinct
    "COUPON_UPC"::bigint as coupon_id,
    "PRODUCT_ID"::bigint as product_id,
    "CAMPAIGN"::integer as campaign_id
from {{ source('dunnhumby_raw', 'coupon') }}
