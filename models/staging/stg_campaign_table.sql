{{ config(materialized='view', alias='stg_campaign_table', grants={'select': ['rol_staging']}) }}

-- Conserva todas las asignaciones, incluidos hogares sin perfil demografico.
SELECT "CAMPAIGN"::integer AS campaign_id,
       household_key::integer AS household_id,
       "DESCRIPTION"::text AS campaign_type
from {{ source('dunnhumby_raw', 'campaign_table') }}
