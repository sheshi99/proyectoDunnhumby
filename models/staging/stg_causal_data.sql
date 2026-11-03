{{ config(materialized='view', alias='stg_causal_data', grants={'select': ['rol_staging']}) }}

-- Conserva filas, ceros, nulos y signos originales; no inventa fechas.
-- display_description y mailer_description traducen los códigos según
-- dunnhumby (2014), The Complete Journey User Guide, página 6.
SELECT "PRODUCT_ID"::bigint AS product_id,
       "STORE_ID"::integer AS store_id,
       "WEEK_NO"::integer AS week_number,
<<<<<<< HEAD
        display::text AS display,
        mailer::text AS mailer
from {{ ref('causal_data') }}
=======
       display::text AS display,
       mailer::text AS mailer,
       case display
           when '0' then 'Not on display'
           when '1' then 'Store front'
           when '2' then 'Store rear'
           when '3' then 'Front end cap'
           when '4' then 'Mid-aisle end cap'
           when '5' then 'Rear end cap'
           when '6' then 'Side-aisle end cap'
           when '7' then 'In-aisle'
           when '9' then 'Secondary location display'
           when 'A' then 'In-shelf'
           else 'Unknown code ' || coalesce(display, 'NULL')
       end AS display_description,
       case mailer
           when '0' then 'Not on ad'
           when 'A' then 'Interior page feature'
           when 'C' then 'Interior page line item'
           when 'D' then 'Front page feature'
           when 'F' then 'Back page feature'
           when 'H' then 'Wrap front feature'
           when 'J' then 'Wrap interior coupon'
           when 'L' then 'Wrap back feature'
           when 'P' then 'Interior page coupon'
           when 'X' then 'Free on interior page'
           when 'Z' then 'Free on front page, back page or wrap'
           else 'Unknown code ' || coalesce(mailer, 'NULL')
       end AS mailer_description
from {{ source('dunnhumby_raw', 'causal_data') }}
>>>>>>> e15da1f28e909e2b4427d04751357c0ac71f139e
