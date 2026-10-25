{{ config(
    materialized='view',
    alias='stg_product',
    grants={'select': ['rol_staging']}
) }}

select
    "PRODUCT_ID"::bigint as product_id,
    "MANUFACTURER"::integer as manufacturer_id,
    nullif(lower(btrim("DEPARTMENT")), '')::text as department,
    nullif(lower(btrim("BRAND")), '')::text as brand,
    nullif(lower(btrim("COMMODITY_DESC")), '')::text as category,
    nullif(lower(btrim("SUB_COMMODITY_DESC")), '')::text as subcategory,
    nullif(lower(btrim("CURR_SIZE_OF_PRODUCT")), '')::text as product_size
from {{ source('dunnhumby_raw', 'product') }}
