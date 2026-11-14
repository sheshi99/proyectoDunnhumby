-- Copia de raw.coupon_redempt en staging; dbt aplica solo las diferencias con el origen.
select * from {{ source('dunnhumby', 'coupon_redempt') }}
