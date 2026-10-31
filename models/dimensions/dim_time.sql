-- Materializa la tabla
-- El target warehouse materializa en Data_warehouse.public
-- Se otorga permiso de lectura al rol rol_data_warehouse
-- Se establece la llave primaria en el campo time_id
-- Obliga a que dataset_day_number y dataset_week_number no sean nulos
-- Se establece que dataset_day_number sea único, para evitar duplicados en la fuente

{{ config(materialized='cambios', unique_key='time_id', schema='public' if target.name == 'warehouse',
    not_null_columns=['dataset_day_number', 'dataset_week_number'], unique_columns=['dataset_day_number']) }}

-- Una fila por día observado en ventas, sin inventar fechas de calendario.
-- Se conserva la semana registrada en la fuente, no se calcula con día / 7.
-- Si un día tiene varias semanas, la clave primaria hace fallar la carga.
select distinct
    transaction_day::bigint as time_id,
    transaction_day::bigint as dataset_day_number,
    transaction_week::bigint as dataset_week_number
from {{ staging_view('stg_transaction_data') }}
