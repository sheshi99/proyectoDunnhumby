{# Actualiza en el sitio: nunca reemplaza tablas ni reasigna identidades.
   En la primera ejecución crea la tabla vacía con sus restricciones y luego la carga. #}
{% materialization cambios, adapter='postgres' %}
  {% if target.name != 'warehouse' %}{{ exceptions.raise_compiler_error('Las tablas incrementales requieren target warehouse') }}{% endif %}
  {% if flags.FULL_REFRESH %}{{ exceptions.raise_compiler_error('Full refresh deshabilitado para conservar datos e IDs') }}{% endif %}
  {% set relation = this.incorporate(type='table') %}
  {% set existing = adapter.get_relation(database=this.database, schema=this.schema, identifier=this.identifier) %}
  {% set identity = config.get('identity_column') %}
  {% if existing is none %}
    {% call statement('crear', auto_begin=True) %}
      {{ crear_tabla(relation, sql, identity, config.get('unique_key'),
          config.get('not_null_columns', []), config.get('unique_columns', []), config.get('foreign_keys', {})) }}
    {% endcall %}
  {% elif existing.type != 'table' %}
    {{ exceptions.raise_compiler_error('Ya existe un objeto que no es tabla: ' ~ this) }}
  {% endif %}
  {% set cols = adapter.get_columns_in_relation(relation) %}
  {% if this.identifier == 'fact_sales' %}
    {% call statement('main', auto_begin=True) %}
      {{ comparar_ventas(relation, sql, cols, identity) }}
    {% endcall %}
  {% else %}
  {% set key = config.require('unique_key') %}
  {% set updates = [] %}{% set names = [] %}{% set values = [] %}{% set comparisons = [] %}
  {% for col in cols if col.name != identity %}
    {% do names.append(adapter.quote(col.name)) %}
    {% do values.append('s.' ~ adapter.quote(col.name)) %}
    {% if col.name != key %}
      {% do updates.append(adapter.quote(col.name) ~ '=s.' ~ adapter.quote(col.name)) %}
      {% do comparisons.append('t.' ~ adapter.quote(col.name) ~ ' is distinct from s.' ~ adapter.quote(col.name)) %}
    {% endif %}
  {% endfor %}
  {% call statement('main', auto_begin=True) %}
    with candidates as materialized ({{ sql }})
    merge into {{ relation }} t using candidates s
    on t.{{ adapter.quote(key) }}=s.{{ adapter.quote(key) }}
    when matched and ({{ comparisons|join(' or ') }}) then update set {{ updates|join(', ') }}
    when not matched then insert ({{ names|join(', ') }}) values ({{ values|join(', ') }})
  {% endcall %}
  {% endif %}
  {% do adapter.commit() %}
  {{ return({'relations': [relation]}) }}
{% endmaterialization %}

{# Crea la tabla con las columnas y tipos del modelo, sin filas. La identidad va
   primero; la clave primaria es la identidad o, si no hay, unique_key. Las claves
   foráneas apuntan a la columna del mismo nombre en la dimensión indicada. #}
{% macro crear_tabla(relation, query, identity, key, not_null_columns, unique_columns, foreign_keys) %}
  create table {{ relation }} as
  select {% if identity %}null::bigint as {{ adapter.quote(identity) }}, {% endif %}s.*
  from (
    {{ query }}
  ) s with no data;
  {% if identity %}
  alter table {{ relation }} alter column {{ adapter.quote(identity) }} set not null;
  alter table {{ relation }} alter column {{ adapter.quote(identity) }} add generated always as identity;
  {% endif %}
  alter table {{ relation }} add primary key ({{ adapter.quote(identity or key) }});
  {% if identity and key %}
  alter table {{ relation }} alter column {{ adapter.quote(key) }} set not null;
  alter table {{ relation }} add unique ({{ adapter.quote(key) }});
  {% endif %}
  {% for col in not_null_columns %}
  alter table {{ relation }} alter column {{ adapter.quote(col) }} set not null;
  {% endfor %}
  {% for col in unique_columns %}
  alter table {{ relation }} add unique ({{ adapter.quote(col) }});
  {% endfor %}
  {% for col, dimension in foreign_keys.items() %}
  alter table {{ relation }} add foreign key ({{ adapter.quote(col) }})
    references {{ relation.incorporate(path={'identifier': dimension}) }} ({{ adapter.quote(col) }});
  {% endfor %}
{% endmacro %}

{# Compara multiconjuntos: conserva coincidencias exactas antes de emparejar
   correcciones con los campos originales. Ningun dato de trabajo se persiste. #}
{% macro comparar_ventas(relation, query, columns, identity='sale_detail_id') %}
  {% set names=[] %}{% set source_values=[] %}{% set target_values=[] %}{% set updates=[] %}
  {% for col in columns if col.name != identity %}
    {% do names.append(adapter.quote(col.name)) %}
    {% do source_values.append('s.' ~ adapter.quote(col.name)) %}
    {% do target_values.append('t.' ~ adapter.quote(col.name)) %}
    {% do updates.append(adapter.quote(col.name) ~ '=s.' ~ adapter.quote(col.name)) %}
  {% endfor %}
  with source_values as (
    select s.*,jsonb_build_array({{ source_values|join(',') }}) as row_value,
      jsonb_build_array(s.household_id,s.basket_id,s.product_id,s.store_id,s.time_id,s.transaction_time) as line_key
    from ({{ query }}) s
  ), source_ranked as materialized (
    select *,row_number() over(partition by row_value order by line_key) as occurrence
    from source_values
  ), target_values as (
    select t.{{ adapter.quote(identity) }},jsonb_build_array({{ target_values|join(',') }}) as row_value,
      jsonb_build_array(t.household_id,t.basket_id,t.product_id,t.store_id,t.time_id,t.transaction_time) as line_key
    from {{ relation }} t
  ), target_ranked as materialized (
    select *,row_number() over(partition by row_value order by {{ adapter.quote(identity) }}) as occurrence
    from target_values
  ), missing_source as materialized (
    select s.* from source_ranked s
    where not exists(select 1 from target_ranked t
      where t.row_value=s.row_value and t.occurrence=s.occurrence)
  ), missing_target as materialized (
    select t.* from target_ranked t
    where not exists(select 1 from source_ranked s
      where s.row_value=t.row_value and s.occurrence=t.occurrence)
  ), source_remaining as (
    select *,row_number() over(partition by line_key order by row_value,occurrence) as line_occurrence
    from missing_source
  ), target_remaining as (
    select *,row_number() over(partition by line_key order by row_value,{{ adapter.quote(identity) }}) as line_occurrence
    from missing_target
  ), differences as (
    select t.{{ adapter.quote(identity) }} as existing_id,
      case when s.line_key is null then 'delete'
           when t.{{ adapter.quote(identity) }} is null then 'insert' else 'update' end as change_kind,
      {{ source_values|join(',') }}
    from source_remaining s full join target_remaining t
      on t.line_key=s.line_key and t.line_occurrence=s.line_occurrence
  )
  merge into {{ relation }} t using differences s
  on t.{{ adapter.quote(identity) }}=s.existing_id
  when matched and s.change_kind='delete' then delete
  when matched and s.change_kind='update' then update set {{ updates|join(',') }}
  when not matched and s.change_kind='insert' then insert ({{ names|join(',') }}) values ({{ source_values|join(',') }})
{% endmacro %}

{% macro remote_query(query, columns) %}
  {{ return("public.dblink('dunnhumby_etl_server', '" ~ query|replace("'", "''") ~ "') as remote_rows(" ~ columns ~ ")") }}
{% endmacro %}

