-- Copia de public.campaign_table en staging; dbt aplica solo las diferencias con el origen.
select * from {{ source('dunnhumby', 'campaign_table') }}
