-- Copia de raw.causal_data en staging; dbt aplica solo las diferencias con el origen.
select * from {{ source('dunnhumby', 'causal_data') }}
