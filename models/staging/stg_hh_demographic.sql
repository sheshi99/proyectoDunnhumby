{{ config(materialized='view', alias='stg_hh_demographic', grants={'select': ['rol_staging']}) }}

-- Conserva todos los perfiles, rangos y categorias originales, incluidas Unknown y None/Unknown.
SELECT household_key::integer AS household_id,
       "AGE_DESC"::text AS age_range,
       "MARITAL_STATUS_CODE"::text AS marital_status_code,
       "INCOME_DESC"::text AS income_range,
       "HOMEOWNER_DESC"::text AS homeownership_status,
       "HH_COMP_DESC"::text AS household_composition,
       "HOUSEHOLD_SIZE_DESC"::text AS household_size_category,
       "KID_CATEGORY_DESC"::text AS children_category
from {{ source('dunnhumby_raw', 'hh_demographic') }}
