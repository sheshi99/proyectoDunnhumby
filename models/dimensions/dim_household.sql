-- Materializa la tabla
-- El target warehouse materializa en Data_warehouse.public
-- Se otorga permiso de lectura al rol rol_data_warehouse
-- dim_household_id es el ID propio del warehouse (IDENTITY) y la llave primaria
-- household_id conserva el código original de Dunnhumby; único y obligatorio

{{ config(materialized='cambios', unique_key='household_id', identity_column='dim_household_id',
    schema='public' if target.name == 'warehouse',
    not_null_columns=['age_group', 'marital_status', 'income_range', 'homeowner_status',
        'household_composition', 'household_size', 'kids_category']) }}

-- La unión de hogares y su perfil se hace en la vista int_household; aquí solo se insertan.
select
    household_id,
    age_group,
    marital_status,
    income_range,
    homeowner_status,
    household_composition,
    household_size,
    kids_category
from {{ staging_view('int_household') }}
