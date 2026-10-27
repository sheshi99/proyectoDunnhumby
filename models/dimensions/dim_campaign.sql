-- Materializa la tabla
-- Se define en el esquema data_warehouse
-- Se otorga permiso de lectura al rol rol_data_warehouse
-- Se establece la llave primaria en el campo campaign_id

{{ config(
    materialized='table',
    schema='data_warehouse',
    grants={'select': ['rol_data_warehouse']},
    post_hook='alter table {{ this }} add primary key (campaign_id)'
) }}

-- Se seleccionan los campos de la vista staging y se renombran 
-- para cumplir con la estructura de la dimensión campaña

select
    campaign_id::bigint as campaign_id,
    campaign_type::text as campaign_description,
    start_day::bigint as start_day,
    end_day::bigint as end_day
from {{ ref('stg_campaign_descriptions') }}
