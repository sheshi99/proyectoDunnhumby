-- Estructura que genera el nombre del esquema de destino para los modelos de dbt.

{% macro generate_schema_name(custom_schema_name, node) -%}
    {# En la segunda base las tablas finales van a public, sin prefijos. #}
    {%- if target.name == 'warehouse' and custom_schema_name in ['public', 'data_warehouse'] -%}
        public
    {%- elif custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif custom_schema_name | trim == 'data_warehouse' -%}
        data_warehouse
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
