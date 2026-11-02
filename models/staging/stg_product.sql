{{ config(
    materialized='view',
    alias='stg_product',
    grants={'select': ['rol_staging']}
) }}

-- Textos vacíos o solo con espacios se reemplazan por 'not available' (Kimball:
-- los atributos de las dimensiones no quedan en NULL).
select
    "PRODUCT_ID"::bigint as product_id,
    "MANUFACTURER"::integer as manufacturer_id,
    coalesce(nullif(lower(btrim("DEPARTMENT")), ''), 'not available')::text as department,
    coalesce(nullif(lower(btrim("BRAND")), ''), 'not available')::text as brand,
    coalesce(nullif(lower(btrim("COMMODITY_DESC")), ''), 'not available')::text as category,
    coalesce(nullif(lower(btrim("SUB_COMMODITY_DESC")), ''), 'not available')::text as subcategory,
    coalesce(nullif(lower(btrim("CURR_SIZE_OF_PRODUCT")), ''), 'not available')::text as product_size
from {{ source('dunnhumby_raw', 'product') }}
