{# Mantiene las copias de staging iguales a las tablas originales de public.
   En la primera ejecución copia la tabla completa; en las siguientes aplica solo
   las diferencias: inserta las filas nuevas y borra las que ya no están en el
   origen. Una fila modificada aparece como su versión anterior (se borra) y su
   versión nueva (se inserta). Las tablas no tienen clave única y hay filas
   repetidas legítimas, por eso se compara cuántas veces aparece cada fila. #}
{% materialization sincronizar_origen, adapter='postgres' %}
  {% if target.name != 'dev' %}{{ exceptions.raise_compiler_error('La sincronización de staging requiere target dev') }}{% endif %}
  {% set relation = this.incorporate(type='table') %}
  {% set existing = adapter.get_relation(database=this.database, schema=this.schema, identifier=this.identifier) %}
  {% if existing is none %}
    {% call statement('main', auto_begin=True) %}
      create table {{ relation }} as {{ sql }}
    {% endcall %}
  {% elif existing.type != 'table' %}
    {{ exceptions.raise_compiler_error('Ya existe un objeto que no es tabla: ' ~ this) }}
  {% else %}
    {% set origen = [] %}{% set destino = [] %}
    {% for col in get_columns_in_query(sql) %}{% do origen.append(col) %}{% endfor %}
    {% for col in adapter.get_columns_in_relation(relation) %}{% do destino.append(col.name) %}{% endfor %}
    {% if origen != destino %}
      {{ exceptions.raise_compiler_error('Las columnas de ' ~ this ~ ' no coinciden con el origen: ' ~ origen ~ ' / ' ~ destino) }}
    {% endif %}
    {% call statement('main', fetch_result=True, auto_begin=True) %}
      {{ aplicar_diferencias(relation, sql) }}
    {% endcall %}
    {% set conteo = load_result('main').table.rows[0] %}
    {% do log(this.identifier ~ ': ' ~ conteo[0] ~ ' filas borradas, ' ~ conteo[1] ~ ' filas insertadas', info=True) %}
  {% endif %}
  {% do adapter.commit() %}
  {{ return({'relations': [relation]}) }}
{% endmaterialization %}

{# EXCEPT ALL respeta las repeticiones: si el origen tiene una fila 3 veces y
   staging 2, falta insertar 1. Solo las filas que difieren se cruzan contra staging. #}
{% macro aplicar_diferencias(relation, query) %}
  create temp table sobran on commit drop as
    select * from {{ relation }} except all select * from ({{ query }}) origen;
  create temp table faltan on commit drop as
    select * from ({{ query }}) origen except all select * from {{ relation }};

  delete from {{ relation }} t
  using (
    select c.fila
    from (
      select x.ctid as fila, x::text as valor,
             row_number() over (partition by x::text) as repeticion
      from {{ relation }} x
      where x::text in (select s::text from sobran s)
    ) c
    join (select s::text as valor, count(*) as cantidad from sobran s group by 1) s
      on s.valor = c.valor
    where c.repeticion <= s.cantidad
  ) borrar
  where t.ctid = borrar.fila;

  insert into {{ relation }} select * from faltan;

  select (select count(*) from sobran) as borradas, (select count(*) from faltan) as insertadas;
{% endmacro %}
