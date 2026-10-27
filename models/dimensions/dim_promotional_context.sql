{{ config(
    materialized='table',
    schema='data_warehouse',
    grants={'select': ['rol_data_warehouse']},
    post_hook=[
        'alter table {{ this }} add column promotional_context_id bigint generated always as identity',
        'alter table {{ this }} add primary key (promotional_context_id)'
    ]
) }}

-- Una fila por combinación de atributos observada en ventas.
-- El identity se genera después de cargar las combinaciones, según el diagrama.
-- Una reconstrucción puede reasignar IDs: al existir fact_sales, su recarga
-- deberá coordinarse con esta dimensión. No conservar claves de una carga previa.
select distinct
    has_promotion,
    display_type,
    mailer_type,
    household_in_active_campaign,
    active_campaigns_count,
    product_associated_with_coupon,
    household_with_redemption_today
from {{ ref('int_sales_promotional_context') }}
