{{ config(materialized='view', alias='stg_campaign_table', grants={'select': ['rol_staging']}) }}

-- Conserva filas, ceros, nulos y valores originales.
SELECT household_key::bigint AS household_key,
       "CAMPAIGN"::bigint AS campaign,
       "DESCRIPTION"::text AS description
from {{ source('dunnhumby_raw', 'campaign_table') }}