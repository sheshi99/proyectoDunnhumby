-- Copia de raw.hh_demographic en staging; dbt aplica solo las diferencias con el origen.
select * from {{ source('dunnhumby', 'hh_demographic') }}
