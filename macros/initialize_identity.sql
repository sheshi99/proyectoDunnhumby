-- Agrega la llave primaria en el primer puesto y 
-- lo deja automatico para la demás


{% macro initialize_identity(relation, column_name) %}
    {# La columna ya ocupa la primera posici?n y contiene IDs de la carga. #}
    alter table {{ relation }} alter column {{ adapter.quote(column_name) }} set not null;
    alter table {{ relation }} alter column {{ adapter.quote(column_name) }}
        add generated always as identity;
    select setval(
        pg_get_serial_sequence('{{ relation }}', '{{ column_name }}'),
        coalesce(max({{ adapter.quote(column_name) }}), 0) + 1,
        false
    ) from {{ relation }};
{% endmacro %}
