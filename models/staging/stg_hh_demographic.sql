{{ config(materialized='view', alias='stg_hh_demographic', grants={'select': ['rol_staging']}) }}

-- Conserva filas, nulos y categorias originales, incluidas Unknown y None/Unknown.
SELECT "AGE_DESC"::text AS age_desc,
       "MARITAL_STATUS_CODE"::text AS marital_status_code,
       "INCOME_DESC"::text AS income_desc,
       "HOMEOWNER_DESC"::text AS homeowner_desc,
       "HH_COMP_DESC"::text AS hh_comp_desc,
       "HOUSEHOLD_SIZE_DESC"::text AS household_size_desc,
       "KID_CATEGORY_DESC"::text AS kid_category_desc,
       household_key::bigint AS household_key
from {{ source('dunnhumby_raw', 'hh_demographic') }}