-- Genera el script sql que permite leer
-- la vista desde otra base de datos, usando dblink.

{% macro staging_view(model_name, alias='staging_source') %}
    {# ref conserva la dependencia dbt; el target warehouse consulta la vista remota. #}
    {% set relation = ref(model_name) %}
    {% if target.name != 'warehouse' or not execute %}
        {{ return(relation ~ ' as ' ~ adapter.quote(alias)) }}
    {% endif %}
    {% set remote_relation = adapter.quote('staging') ~ '.' ~ adapter.quote(model_name) %}
    {% set metadata_sql %}
        select string_agg(format('%I %s', attname,
            pg_catalog.format_type(atttypid, atttypmod)), ', ' order by attnum)
        from pg_catalog.pg_attribute
        where attrelid = '{{ remote_relation }}'::regclass
          and attnum > 0 and not attisdropped
    {% endset %}
    {% set metadata_query %}
        select definition from public.dblink(
            'dunnhumby_etl_server',
            '{{ metadata_sql | replace("'", "''") }}'
        ) as metadata(definition text)
    {% endset %}
    {% set result = run_query(metadata_query) %}
    {% if result | length != 1 or result.rows[0][0] is none %}
        {{ exceptions.raise_compiler_error('No se encontraron columnas para ' ~ remote_relation) }}
    {% endif %}
    {% set query = 'select * from ' ~ remote_relation %}
    {{ return("public.dblink('dunnhumby_etl_server', '"
        ~ query|replace("'", "''") ~ "') as " ~ adapter.quote(alias)
        ~ '(' ~ result.rows[0][0] ~ ')') }}
{% endmacro %}
