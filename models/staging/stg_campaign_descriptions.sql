

{{ config(
    materialized='view', 
    alias='stg_campaign_descriptions', 
    grants={'select': ['rol_staging']}
) }}

select
    "CAMPAIGN"::integer        as campaign_id,   -- Conversión a integer y estandarización como llave primaria
    trim("DESCRIPTION")        as campaign_type, -- Limpieza de espacios manteniendo el formato original (TypeA, TypeB...)
    "START_DAY"::integer       as start_day,     -- Conversión a integer del día de inicio de la campaña
    "END_DAY"::integer         as end_day        -- Conversión a integer del día de cierre de la campaña
from {{ source('dunnhumby_raw', 'campaign_desc') }}