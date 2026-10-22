# Inicialización de dbt con PostgreSQL

Esta etapa configura dbt Core localmente. No requiere una cuenta de dbt.
dbt se conecta a PostgreSQL, el servidor donde está la base. pgAdmin es otra
aplicación para administrar ese servidor: no se conecta dbt a pgAdmin.
No necesitas mantener pgAdmin abierto; sí debe estar iniciado PostgreSQL.
Los comandos se ejecutan en la terminal PowerShell de VS Code, no en Query Tool.

## Antes de empezar

Utiliza tu entorno virtual `venv` existente y el repositorio actualizado.
PostgreSQL debe estar iniciado y la base `dunnhumby_etl` debe existir.
Ten a mano el usuario y la contraseña de PostgreSQL.

## 1. Instalar en el entorno virtual existente

Abre **Terminal → Nueva terminal** en VS Code, usa PowerShell y entra a la
carpeta del proyecto (ajusta la ruta si lo descargaste en otro lugar):

```powershell
cd C:\Proyecto_Mineria\proyectoDunnhumby
```

Con tu entorno virtual existente activo (debe aparecer `(venv)`), instala dbt:

```powershell
python -m pip install -r requirements-dbt.txt
```

Cuando termine, comprueba la instalación:

```powershell
dbt --version
```

La salida debe mostrar Core y el adaptador `postgres`.

## 2. Preparar el perfil local

Cada integrante debe crear `profiles.yml` en la raíz del repositorio,
junto a `dbt_project.yml`. Este archivo indica a dbt cómo conectarse.
Si ya existe, comprueba su contenido. Utiliza este ejemplo completo:

```yaml
dunnhumby:
  target: dev
  outputs:
    dev:
      type: postgres
      host: "{{ env_var('DBT_PG_HOST', 'localhost') }}"
      port: "{{ env_var('DBT_PG_PORT', '5432') | int }}"
      user: "{{ env_var('DBT_PG_USER', 'postgres') }}"
      password: "{{ env_var('DBT_ENV_SECRET_PG_PASSWORD') }}"
      dbname: dunnhumby_etl
      schema: dbt_dev
      threads: 4
      connect_timeout: 10
```

Conserva la indentación con espacios, sin tabulaciones.

| Campo | Función |
| --- | --- |
| `dunnhumby` | Nombre del perfil al que apunta `dbt_project.yml`. |
| `target: dev` | Selecciona la conexión `dev` definida bajo `outputs`. |
| `type: postgres` | Selecciona el adaptador de PostgreSQL. |
| `host`, `port`, `user` | Datos del servidor y usuario; leen variables o usan los valores predeterminados. |
| `password` | Lee la contraseña del entorno sin escribirla en el archivo. |
| `dbname` | Base de datos de destino. |
| `schema: dbt_dev` | Esquema para los futuros modelos; las fuentes siguen en `staging`. |
| `threads: 4` | Número de tareas que dbt puede ejecutar en paralelo. |
| `connect_timeout: 10` | Tiempo límite para conectarse, en segundos. |

`env_var(...)` lee una variable del entorno de la terminal. El `.gitignore`
excluye `profiles.yml`, por lo que cada integrante conserva su configuración
local sin subirla a Git. Este documento contiene la plantilla compartida.

El perfil usa por defecto `localhost`, puerto `5432`, usuario `postgres`
y base `dunnhumby_etl`. Comprobar estos datos contra la conexión de pgAdmin.
Si son distintos, ajusta los valores predeterminados correspondientes en tu
perfil local. Si la base tiene otro nombre, cambia `dbname`.

## 3. Introducir la contraseña sin guardarla en archivos

Ejecuta **una línea a la vez**, presionando Enter después de cada una.

Copia esta primera línea exactamente como aparece; no reemplaces el texto
`Contraseña de PostgreSQL`:

```powershell
$dbtPassword = Read-Host 'Contraseña de PostgreSQL' -AsSecureString
```

Cuando aparezca `Contraseña de PostgreSQL:`, escribe tu contraseña real y
presiona Enter. No se mostrará como texto visible. El texto entre comillas
del comando es solo la etiqueta de la pregunta. Si te equivocas, cancela
con Ctrl+C y repite este paso.

Después ejecuta esta segunda línea sin modificarla:

```powershell
$env:DBT_ENV_SECRET_PG_PASSWORD = [System.Net.NetworkCredential]::new('', $dbtPassword).Password
```

Esta línea pone la contraseña en la variable que lee el perfil. Luego ejecuta:

```powershell
Remove-Variable dbtPassword
```

Elimina la variable temporal; la variable de entorno que necesita dbt sigue
disponible. Es normal que las dos últimas líneas no impriman mensajes.

Es la contraseña del usuario de PostgreSQL, no la contraseña maestra de pgAdmin.
La variable queda disponible para dbt durante esta sesión. No compartas la
contraseña ni la escribas en el repositorio.

## 4. Validar la conexión

Con PostgreSQL iniciado y desde la raíz del repositorio:

```powershell
dbt debug --profiles-dir .
```

Es el comando `dbt debug` con la ubicación del perfil indicada explícitamente.
El punto indica que debe buscar `profiles.yml` en la carpeta actual.
La salida de la prueba aparece en la terminal, no en una ventana de pgAdmin:

```text
profiles.yml file [OK found and valid]
dbt_project.yml file [OK found and valid]
Connection test: [OK connection ok]
All checks passed!
```

Debe informar archivos válidos, `Connection test: [OK connection ok]` y
`All checks passed!`. Guardar la salida o una captura, la fecha y la versión
de dbt como evidencia en Jira. La configuración no debe darse por validada
hasta obtener ese resultado con la base real.
No hace falta ejecutar `dbt run` para este criterio.
dbt se conecta cuando ejecutas comandos que necesitan la base; no queda
una conexión abierta permanentemente.

## 5. Volver a trabajar en otra sesión

La instalación y los archivos permanecen guardados. No debes reinstalar
dbt ni recrear el perfil cada vez. En una terminal nueva, entra a la carpeta
del proyecto y repite el paso 3 para introducir la contraseña. Si utilizas
otro entorno virtual, comprueba que esté activo. Después ejecuta la prueba
del paso 4.
