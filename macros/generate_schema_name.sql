{% macro generate_schema_name(custom_schema_name, node) -%}
    {# Las tablas finales van exactamente a data_warehouse, sin prefijo staging_. #}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- elif custom_schema_name | trim == 'data_warehouse' -%}
        data_warehouse
    {%- else -%}
        {{ target.schema }}_{{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
