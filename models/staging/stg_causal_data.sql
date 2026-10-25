{{ config(materialized='view', alias='stg_causal_data', grants={'select': ['rol_staging']}) }}

-- Conserva filas, ceros, nulos y signos originales; no inventa fechas.
SELECT "PRODUCT_ID"::bigint AS product_id, 
        "STORE_ID"::integer AS store_id,
       "WEEK_NO"::integer AS week_no, 
       display::text AS display, 
       mailer::text AS mailer
from {{ source('dunnhumby_raw', 'causal_data') }}
