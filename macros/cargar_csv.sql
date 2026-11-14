{# Carga inicial masiva dirigida por dbt. PostgreSQL lee los CSV mediante COPY.
   El servicio PostgreSQL debe poder leer la carpeta.
   Si la ruta tiene tildes, PostgreSQL lee el archivo con COPY ... FROM PROGRAM
   (PowerShell), porque en Windows no abre esas rutas directamente.
   La validación de los ocho encabezados ocurre antes de crear o vaciar tablas.
   Todas las cargas seleccionadas se confirman en una sola transacción. #}
{% macro cargar_csv(directorio_csv=none, esquema='public', tablas=none, reemplazar=false, solo_validar=false) %}
  {% if not directorio_csv %}
    {# Por defecto, la carpeta database/ del proyecto; no hay que escribir rutas. #}
    {% set directorio_csv = (invocation_args_dict.get('project_dir') | string | replace('\\', '/')).rstrip('/') ~ '/database' %}
  {% endif %}
  {% if target.name != 'dev' %}
    {{ exceptions.raise_compiler_error('cargar_csv requiere --target dev; nunca carga CSV en el warehouse.') }}
  {% endif %}
  {% if esquema != 'public' and not esquema.startswith('carga_csv_') %}
    {{ exceptions.raise_compiler_error('Usar public o un esquema de prueba cuyo nombre empiece por carga_csv_. No se permite cargar en staging.') }}
  {% endif %}
  {% if reemplazar not in [true, false] or solo_validar not in [true, false] %}
    {{ exceptions.raise_compiler_error('reemplazar y solo_validar deben ser booleanos JSON: true o false, sin comillas.') }}
  {% endif %}
  {% set carpeta = directorio_csv | replace('\\', '/') %}
  {% if '$dbt_csv$' in carpeta %}
    {{ exceptions.raise_compiler_error('La ruta no puede contener el delimitador reservado $dbt_csv$.') }}
  {% endif %}
  {% if carpeta | length < 3 or not (carpeta.startswith('/') or carpeta[1:3] == ':/') %}
    {{ exceptions.raise_compiler_error('directorio_csv debe ser una ruta absoluta del servidor PostgreSQL; usar / en Windows.') }}
  {% endif %}
  {% set carpeta = carpeta.rstrip('/') %}
  {% if not ruta_es_ascii(carpeta) and ('"' in carpeta or '%' in carpeta) %}
    {{ exceptions.raise_compiler_error('La ruta de los CSV no puede contener comillas dobles ni %.') }}
  {% endif %}
  {% set definiciones = {
    'campaign_desc': [('DESCRIPTION','text'),('CAMPAIGN','bigint'),('START_DAY','bigint'),('END_DAY','bigint')],
    'campaign_table': [('DESCRIPTION','text'),('household_key','bigint'),('CAMPAIGN','bigint')],
    'causal_data': [('PRODUCT_ID','bigint'),('STORE_ID','bigint'),('WEEK_NO','bigint'),('display','text'),('mailer','text')],
    'coupon': [('COUPON_UPC','bigint'),('PRODUCT_ID','bigint'),('CAMPAIGN','bigint')],
    'coupon_redempt': [('household_key','bigint'),('DAY','bigint'),('COUPON_UPC','bigint'),('CAMPAIGN','bigint')],
    'hh_demographic': [('AGE_DESC','text'),('MARITAL_STATUS_CODE','text'),('INCOME_DESC','text'),('HOMEOWNER_DESC','text'),('HH_COMP_DESC','text'),('HOUSEHOLD_SIZE_DESC','text'),('KID_CATEGORY_DESC','text'),('household_key','bigint')],
    'product': [('PRODUCT_ID','bigint'),('MANUFACTURER','bigint'),('DEPARTMENT','text'),('BRAND','text'),('COMMODITY_DESC','text'),('SUB_COMMODITY_DESC','text'),('CURR_SIZE_OF_PRODUCT','text')],
    'transaction_data': [('household_key','bigint'),('BASKET_ID','bigint'),('DAY','bigint'),('PRODUCT_ID','bigint'),('QUANTITY','bigint'),('SALES_VALUE','double precision'),('STORE_ID','bigint'),('RETAIL_DISC','double precision'),('TRANS_TIME','bigint'),('WEEK_NO','bigint'),('COUPON_DISC','double precision'),('COUPON_MATCH_DISC','double precision')]
  } %}
  {% set elegidas = definiciones.keys() | list if tablas is none else tablas %}
  {% if elegidas is string or elegidas | length == 0 %}
    {{ exceptions.raise_compiler_error('tablas debe ser una lista no vacía; omitir para cargar las ocho tablas.') }}
  {% endif %}
  {% if elegidas | unique | list | length != elegidas | length %}
    {{ exceptions.raise_compiler_error('No repetir nombres en tablas.') }}
  {% endif %}
  {% for nombre in elegidas %}
    {% if nombre not in definiciones %}
      {{ exceptions.raise_compiler_error('Tabla CSV no permitida: ' ~ nombre) }}
    {% endif %}
  {% endfor %}
  {% if not execute %}{{ return(none) }}{% endif %}

  {# BEGIN explícito: no depender del modo implícito/autocommit del controlador. #}
  {% call statement('iniciar_carga_csv', auto_begin=True) %}
    begin
  {% endcall %}
  {# El bloqueo evita dos cargas iniciales simultáneas dirigidas por esta macro. #}
  {% call statement('bloqueo_csv', fetch_result=True, auto_begin=True) %}
    select pg_try_advisory_xact_lock(hashtext('dunnhumby_cargar_csv'))
  {% endcall %}
  {% if not load_result('bloqueo_csv').table.rows[0][0] %}
    {{ exceptions.raise_compiler_error('Ya hay otra carga CSV activa. Esperar a que termine.') }}
  {% endif %}

  {% for nombre in elegidas %}
    {% set archivo = (carpeta ~ '/' ~ nombre ~ '.csv') | replace("'", "''") %}
    {% set cabecera = [] %}
    {% for columna, tipo in definiciones[nombre] %}{% do cabecera.append(columna) %}{% endfor %}
    {% set ayuda = 'Si es la primera vez en este equipo, dar lectura al servicio PostgreSQL (ver docs/carga_csv_dbt.md): icacls "' ~ carpeta.replace('/', '\\') ~ '" /grant "*S-1-5-20:(OI)(CI)RX"' %}
    {% call statement('validar_archivo_csv', auto_begin=True) %}
      do $dbt_csv$
      declare encabezado text;
      begin
        begin
          {% if ruta_es_ascii(archivo) %}
          encabezado := split_part(pg_read_file('{{ archivo }}', 0, 4096), chr(10), 1);
          {% else %}
          create temp table if not exists encabezado_csv(linea text) on commit drop;
          truncate encabezado_csv;
          execute 'copy encabezado_csv from program ' || quote_literal('{{ comando_leer_csv(archivo, solo_encabezado=true) | replace("'", "''") }}');
          select linea into encabezado from encabezado_csv limit 1;
          {% endif %}
          encabezado := rtrim(ltrim(encabezado, chr(65279)), chr(13));
        exception when others then
          raise exception 'PostgreSQL no puede leer %. % Detalle: %', '{{ archivo }}', '{{ ayuda | replace("'", "''") }}', SQLERRM;
        end;
        if encabezado is distinct from '{{ cabecera | join(',') }}' then
          raise exception 'Encabezado incorrecto en %. Esperado: %. Recibido: %', '{{ archivo }}', '{{ cabecera | join(',') }}', encabezado;
        end if;
      end $dbt_csv$;
    {% endcall %}
    {% set actual = adapter.get_relation(database=target.database, schema=esquema, identifier=nombre) %}
    {% if actual is not none %}
      {% if actual.type != 'table' %}
        {{ exceptions.raise_compiler_error(esquema ~ '.' ~ nombre ~ ' existe y no es una tabla. No se modificó.') }}
      {% endif %}
      {% if not reemplazar and not solo_validar %}
        {{ exceptions.raise_compiler_error(esquema ~ '.' ~ nombre ~ ' ya existe. No se reemplaza por defecto; usar un esquema carga_csv_ de prueba o reemplazar: true explícitamente.') }}
      {% endif %}
      {# Evita truncar si el orden, nombre o tipo difiere de la definición esperada. #}
      {% set columnas_actuales = adapter.get_columns_in_relation(actual) %}
      {% set firma_actual = [] %}
      {% set firma_esperada = [] %}
      {% for columna in columnas_actuales %}{% do firma_actual.append((columna.name, columna.data_type | lower)) %}{% endfor %}
      {% for columna, tipo in definiciones[nombre] %}{% do firma_esperada.append((columna, tipo)) %}{% endfor %}
      {% if firma_actual != firma_esperada %}
        {{ exceptions.raise_compiler_error('La estructura de ' ~ esquema ~ '.' ~ nombre ~ ' difiere de la esperada. No se reemplaza; revisar tipos y orden de columnas.') }}
      {% endif %}
    {% endif %}
    {% do log('CSV validado: ' ~ nombre, info=True) %}
  {% endfor %}

  {% if solo_validar %}
    {% do adapter.commit() %}
    {% do log('Validación terminada. No se crearon tablas ni se cargaron datos.', info=True) %}
    {{ return(none) }}
  {% endif %}

  {% call statement('crear_esquema_csv', auto_begin=True) %}
    create schema if not exists {{ adapter.quote(esquema) }}
  {% endcall %}
  {% for nombre in elegidas %}
    {% set destino = adapter.quote(esquema) ~ '.' ~ adapter.quote(nombre) %}
    {% set columnas = [] %}
    {% set columnas_tipos = [] %}
    {% for columna, tipo in definiciones[nombre] %}
      {% do columnas.append(adapter.quote(columna)) %}
      {% do columnas_tipos.append(adapter.quote(columna) ~ ' ' ~ tipo) %}
    {% endfor %}
    {% set archivo = (carpeta ~ '/' ~ nombre ~ '.csv') | replace("'", "''") %}
    {% do log('Cargando ' ~ destino ~ ' mediante COPY...', info=True) %}
    {% call statement('copiar_csv', auto_begin=True) %}
      create table if not exists {{ destino }} ({{ columnas_tipos | join(', ') }});
      {% if reemplazar %}truncate table {{ destino }};{% endif %}
      copy {{ destino }} ({{ columnas | join(', ') }})
        from {% if ruta_es_ascii(archivo) %}'{{ archivo }}'{% else %}program '{{ comando_leer_csv(archivo) | replace("'", "''") }}'{% endif %}
        with (format csv, header true, encoding 'UTF8');
    {% endcall %}
    {% set conteo = run_query('select count(*) from ' ~ destino) %}
    {% do log(nombre ~ ': ' ~ conteo.rows[0][0] ~ ' filas cargadas (pendientes de confirmación hasta finalizar todas las tablas).', info=True) %}
  {% endfor %}
  {% do adapter.commit() %}
  {% do log('Carga CSV confirmada. Staging y el warehouse se actualizan después con los comandos dbt build habituales.', info=True) %}
{% endmacro %}

{# True si la ruta solo tiene caracteres ASCII. PostgreSQL en Windows no abre
   rutas con tildes (por ejemplo "Minería"); en ese caso se lee con PowerShell. #}
{% macro ruta_es_ascii(ruta) %}
  {{ return(ruta.isascii()) }}
{% endmacro %}

{# Comando que PostgreSQL ejecuta con COPY ... FROM PROGRAM para leer un CSV cuya
   ruta tiene tildes. Cada letra acentuada se escribe como [char]código, así el
   comando queda en ASCII y PowerShell reconstruye la ruta exacta. Envía el archivo
   tal cual (bytes UTF-8) o, para validar, solo su primera línea. #}
{% macro comando_leer_csv(archivo, solo_encabezado=false) %}
  {% set codigos = {'á': 225, 'é': 233, 'í': 237, 'ó': 243, 'ú': 250, 'Á': 193, 'É': 201,
      'Í': 205, 'Ó': 211, 'Ú': 218, 'ñ': 241, 'Ñ': 209, 'ü': 252, 'Ü': 220, 'à': 224,
      'è': 232, 'ì': 236, 'ò': 242, 'ù': 249, 'ç': 231, 'Ç': 199} %}
  {% set partes = [] %}
  {% set tramo = namespace(texto='') %}
  {% for letra in archivo %}
    {% if letra in codigos %}
      {% if tramo.texto %}{% do partes.append("'" ~ tramo.texto ~ "'") %}{% endif %}
      {% do partes.append('[char]' ~ codigos[letra]) %}
      {% set tramo.texto = '' %}
    {% elif not letra.isascii() %}
      {{ exceptions.raise_compiler_error('La ruta de los CSV tiene un carácter no soportado: ' ~ letra) }}
    {% else %}
      {% set tramo.texto = tramo.texto ~ letra %}
    {% endif %}
  {% endfor %}
  {% if tramo.texto %}{% do partes.append("'" ~ tramo.texto ~ "'") %}{% endif %}
  {% set ruta = '(' ~ partes | join('+') ~ ')' %}
  {% if solo_encabezado %}
    {% set script = 'Get-Content -LiteralPath ' ~ ruta ~ ' -TotalCount 1 -Encoding UTF8' %}
  {% else %}
    {% set script = '$o=[Console]::OpenStandardOutput(); $s=[IO.File]::OpenRead(' ~ ruta ~ '); $s.CopyTo($o); $o.Flush(); $s.Close()' %}
  {% endif %}
  {{ return('powershell -NoProfile -NonInteractive -Command "$ErrorActionPreference=' ~ "'Stop'" ~ '; ' ~ script ~ '"') }}
{% endmacro %}
