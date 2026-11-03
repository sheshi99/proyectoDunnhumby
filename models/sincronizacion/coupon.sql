-- Copia de public.coupon en staging; dbt aplica solo las diferencias con el origen.
select * from {{ source('dunnhumby', 'coupon') }}
