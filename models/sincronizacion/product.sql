-- Copia de public.product en staging; dbt aplica solo las diferencias con el origen.
select * from {{ source('dunnhumby', 'product') }}
