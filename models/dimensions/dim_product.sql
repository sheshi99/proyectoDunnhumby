-- Materializa la tabla
-- Se define en el esquema data_warehouse
-- Se otorga permiso de lectura al rol rol_data_warehouse
-- Se establece la llave primaria en el campo product_id

{{ config(
    materialized='table',
    schema='data_warehouse',
    grants={'select': ['rol_data_warehouse']},
    post_hook='alter table {{ this }} add primary key (product_id)'
) }}

-- Se seleccionan los campos de la vista staging y se renombran 
-- para cumplir con la estructura de la dimensión producto

select
    product_id::bigint as product_id,
    manufacturer_id::bigint as manufacturer,
    department::text as department,
    brand::text as brand,
    category::text as category,
    subcategory::text as subcategory,
    product_size::text as product_size
from {{ ref('stg_product') }}
