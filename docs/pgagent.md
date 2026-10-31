# Configuración de pgAgent

Esta guía describe cómo se configuró la ejecución automática y los pasos para
repetirla en otro equipo. El funcionamiento del job se explica en la
[guía del job](job_etl.md).

## Componentes

| Componente | Ubicación |
| --- | --- |
| Job y horario | Base `postgres`, esquema `pgagent`, visibles en pgAdmin. |
| Servicio de Windows | `DunnhumbyPgAgent`, con la cuenta `LocalService`. |
| Lanzador | [ejecutar_dbt_pgagent.ps1](../scripts/ejecutar_dbt_pgagent.ps1) |
| Credencial del servicio | `logs/jobs/pgagent.pgpass`, excluida de Git y con acceso restringido. |
| Credenciales de dbt | `.env` y `profiles.yml`, excluidos de Git. |

El servicio solo puede leer el código del proyecto y Python, y escribir en
`logs/` y `target/`. La contraseña no aparece en el comando del servicio.
El Programador de tareas de Windows ya no se utiliza.

## Requisitos

- Pasos 1 a 10 del [README](../README.md) completos y las tablas del warehouse creadas.
- Extensión pgAgent instalada en PostgreSQL
  ([instalación](https://www.pgadmin.org/docs/pgadmin4/latest/pgagent_install.html)).
- `python-dotenv[cli]` instalado en el mismo entorno que dbt.
- La carpeta del proyecto disponible localmente (no solo en la nube de OneDrive).

## Pasos de instalación

En la instalación actual ya está todo activo. Repetir estos pasos solo en un
equipo nuevo, si cambia la ubicación del proyecto o de dbt, o si cambian las
credenciales. No ejecutarlos mientras el job esté corriendo.

1. **Comprobar las conexiones y generar los comandos del job.** Desde la raíz
   del repositorio:

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\preparar_pgagent.ps1
   ```

   Ejecuta `dbt debug` en ambas conexiones y genera en `logs/jobs/` los archivos
   `.cmd` que usará pgAgent. Las rutas van codificadas para conservar tildes y
   espacios; no incluyen contraseñas.

2. **Registrar el servicio y el job.** En PowerShell abierto como administrador:

   ```powershell
   .\scripts\registrar_pgagent.ps1
   ```

   Toma las credenciales de `.env`, crea el archivo `pgpass`, registra el servicio
   `DunnhumbyPgAgent` y guarda el job con su horario, ambos deshabilitados.
   Si PostgreSQL no es la versión 15, indicar `-PgAgentExecutable` y `-PsqlExecutable`.

3. **Probar el job.** En pgAdmin, abrir **pgAgent Jobs →
   Dunnhumby_ETL_cada_2_horas**, usar **Run now** y comprobar en **Statistics**
   que termine con código 0.

4. **Habilitar el horario.** En las propiedades del job, activar el job y el
   horario **Cada dos horas** (minuto 00; horas 00, 02, …, 22; todos los días y
   meses). Revisar **Next run**; el servidor del proyecto usa UTC−06:00.

## Cambio de credenciales

Actualizar `.env`, repetir el paso 2 y reiniciar el servicio `DunnhumbyPgAgent`
cuando no haya una ejecución en curso. Después, habilitar de nuevo el job (paso 4).

## Referencias

- [Jobs, pasos y horarios de pgAgent](https://www.pgadmin.org/docs/pgadmin4/latest/pgagent_jobs.html).
- [Materializaciones de dbt](https://docs.getdbt.com/guides/create-new-materializations).
