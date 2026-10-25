{{ config(materialized='view', alias='stg_transaction_data', grants={'select': ['rol_staging']}) }}

-- Conserva filas, ceros, nulos y signos originales; no inventa fechas.
SELECT household_key::integer AS household_key, 
       "BASKET_ID"::bigint AS basket_id,
       "DAY"::integer AS transaction_day,
       "PRODUCT_ID"::bigint AS product_id,
       "QUANTITY"::integer AS quantity, 
       "SALES_VALUE"::numeric AS sales_value,
       "STORE_ID"::integer AS store_id, 
       "RETAIL_DISC"::numeric AS retail_discount,
       "TRANS_TIME"::integer AS transaction_time_hhmm, 
       "WEEK_NO"::integer AS transaction_week,
       "COUPON_DISC"::numeric AS coupon_discount, 
       "COUPON_MATCH_DISC"::numeric AS coupon_match_discount
from {{ source('dunnhumby_raw', 'transaction_data') }}
