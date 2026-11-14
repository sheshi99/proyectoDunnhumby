{# Hook on-run-start: carga los CSV de database/ en public durante el primer
   dbt build --target dev --vars "{cargar_csv: true}".
   Sin esa variable no hace nada (por ejemplo, en el job diario).
   La carpeta se toma del proyecto; no hay que escribir rutas en .env.
   Opcional: --vars "{cargar_csv: true, directorio_csv: 'C:/otra/carpeta'}". #}
{% macro cargar_csv_al_iniciar() %}
  {% if not execute or flags.WHICH != 'build' %}{{ return('') }}{% endif %}
  {% set solicitado = var('cargar_csv', false) %}
  {% if solicitado is not sameas true and solicitado is not sameas false %}
    {{ exceptions.raise_compiler_error('La variable cargar_csv debe ser true o false, sin comillas.') }}
  {% endif %}
  {% if not solicitado %}{{ return('') }}{% endif %}
  {% if target.name != 'dev' %}
    {{ exceptions.raise_compiler_error('La carga CSV inicial se solicita solamente con --target dev.') }}
  {% endif %}
  {# Sin directorio_csv, cargar_csv usa la carpeta database/ del proyecto. #}
  {% do cargar_csv(directorio_csv=var('directorio_csv', none), esquema='public') %}
  {{ return('') }}
{% endmacro %}
