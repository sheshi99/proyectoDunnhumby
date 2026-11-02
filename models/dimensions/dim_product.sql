-- Materializa la tabla
-- El target warehouse materializa en Data_warehouse.public
-- Se otorga permiso de lectura al rol rol_data_warehouse
-- dim_product_id es el ID propio del warehouse (IDENTITY) y la llave primaria
-- product_id conserva el código original de Dunnhumby; único y obligatorio

{{ config(materialized='cambios', unique_key='product_id', identity_column='dim_product_id',
    schema='public' if target.name == 'warehouse',
    not_null_columns=['manufacturer', 'department', 'brand', 'category', 'subcategory', 'product_size']) }}

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
from {{ staging_view('stg_product') }}
