{{ config(materialized='view', grants={'select': ['rol_staging']}) }}

-- Una fila por día del dataset con sus atributos de calendario.
-- Basada en la DIM_TIEMPO del curso, adaptada a PostgreSQL.
-- La fecha viene de stg_transaction_data (fecha base + día del dataset).
-- Se conserva la semana original del dataset, que usan los datos causales.
-- Los textos van en inglés, igual que el resto del modelo.
with days as (
    select distinct
        transaction_day,
        transaction_date,
        transaction_week
    from {{ ref('stg_transaction_data') }}
), parts as (
    select
        days.*,
        extract(year from transaction_date)::integer as calendar_year,
        extract(quarter from transaction_date)::integer as calendar_quarter,
        extract(month from transaction_date)::integer as calendar_month,
        -- Igual que DATEPART(week): la semana empieza en domingo y la semana 1 contiene el 1 de enero.
        (extract(doy from transaction_date)::integer
            + extract(dow from date_trunc('year', transaction_date))::integer - 1) / 7 + 1 as week_of_year,
        extract(day from transaction_date)::integer as day_of_month,
        -- Igual que DATEPART(dw): 1 = domingo ... 7 = sábado.
        extract(dow from transaction_date)::integer + 1 as day_of_week,
        extract(doy from transaction_date)::integer as day_of_year
    from days
)
select
    to_char(transaction_date, 'YYYYMMDD')::integer as date_key,
    transaction_date as calendar_date,
    transaction_day as dataset_day_number,
    transaction_week as dataset_week_number,
    calendar_year,
    calendar_quarter,
    calendar_month,
    week_of_year,
    day_of_month,
    day_of_week,
    day_of_year,
    'Q' || calendar_quarter || '/' || to_char(transaction_date, 'YY') as quarter_name,
    to_char(transaction_date, 'FMMonth') as month_name,
    to_char(transaction_date, 'Mon') as month_short_name,
    'Week ' || week_of_year || '/' || to_char(transaction_date, 'YY') as week_name,
    to_char(transaction_date, 'DD Mon') as day_name,
    to_char(transaction_date, 'FMDay') as day_of_week_name
from parts
