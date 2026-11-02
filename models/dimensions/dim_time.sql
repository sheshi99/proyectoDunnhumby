-- Materializa la tabla
-- El target warehouse materializa en Data_warehouse.public
-- Se otorga permiso de lectura al rol rol_data_warehouse
-- Se establece la llave primaria en el campo dim_time_id (fecha como AAAAMMDD)
-- Obliga a que todas las columnas sean obligatorias, como la DIM_TIEMPO del curso
-- Se establece que dataset_day_number y calendar_date sean únicos

{{ config(materialized='cambios', unique_key='dim_time_id', schema='public' if target.name == 'warehouse',
    not_null_columns=['calendar_date', 'dataset_day_number', 'dataset_week_number', 'calendar_year',
        'calendar_quarter', 'calendar_month', 'week_of_year', 'day_of_month', 'day_of_week', 'day_of_year',
        'quarter_name', 'month_name', 'month_short_name', 'week_name', 'day_name', 'day_of_week_name'],
    unique_columns=['dataset_day_number', 'calendar_date']) }}

-- Los cálculos de calendario se hacen en la vista int_time; aquí solo se insertan.
select
    date_key as dim_time_id,
    calendar_date,
    dataset_day_number,
    dataset_week_number,
    calendar_year,
    calendar_quarter,
    calendar_month,
    week_of_year,
    day_of_month,
    day_of_week,
    day_of_year,
    quarter_name,
    month_name,
    month_short_name,
    week_name,
    day_name,
    day_of_week_name
from {{ staging_view('int_time') }}
