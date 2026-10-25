{{ config(materialized='view', alias='stg_hh_demographic', grants={'select': ['rol_staging']}) }}

-- Conserva filas, nulos y categorias originales, incluidas Unknown y None/Unknown.
SELECT age_desc::text AS age_desc,
       marital_status_code::text AS marital_status_code,
       income_desc::text AS income_desc,
       homeowner_desc::text AS homeowner_desc,
       hh_comp_desc::text AS hh_comp_desc,
       household_size_desc::text AS household_size_desc,
       kid_category_desc::text AS kid_category_desc,
       household_key::bigint AS household_key
from {{ source('dunnhumby_raw', 'hh_demographic') }}