-- Copia de public.transaction_data en staging; dbt aplica solo las diferencias con el origen.
select * from {{ source('dunnhumby', 'transaction_data') }}
