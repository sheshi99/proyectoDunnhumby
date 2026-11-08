# Ejecución y configuración del job ETL

El job `Dunnhumby_ETL_madrugada` se ejecuta todos los días a las 2:00 a. m.;
sincroniza staging con `public` y actualiza
`Data_warehouse` desde staging.
Usa tres ejecutables de la carpeta `scripts/`. Todos los comandos se ejecutan en
PowerShell desde la carpeta del proyecto.

Esta guía corresponde al paso 11 del [README](../README.md). Explica qué hace el
job, cómo se configuró la ejecución automática con pgAgent y los pasos para
repetirla en otro equipo.

## 1. Componentes

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

## 2. Requisitos

- Pasos 1 a 10 del [README](../README.md) completos y las tablas del warehouse creadas.
- Extensión pgAgent instalada en PostgreSQL
  ([instalación](https://www.pgadmin.org/docs/pgadmin4/latest/pgagent_install.html)).
- `python-dotenv[cli]` instalado en el mismo entorno que dbt.
- La carpeta del proyecto disponible localmente (no solo en la nube de OneDrive).

## 3. Instalación

En la instalación actual ya está todo activo. Repetir estos pasos solo en un
equipo nuevo, si cambia la ubicación del proyecto o de dbt, o si cambian las
credenciales. No ejecutarlos mientras el job esté corriendo.

### Paso 1. Preparar (una sola vez)

Comprobar las conexiones y generar los comandos del job. Desde la raíz del
repositorio:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\preparar_pgagent.ps1
```

[preparar_pgagent.ps1](../scripts/preparar_pgagent.ps1) ejecuta `dbt debug` en
ambas conexiones y crea en `logs/jobs/` los archivos `pgagent_ejecutar.cmd` y
`pgagent_comprobar.cmd`, que son los que llama pgAgent. Las rutas van
codificadas para conservar tildes y espacios; no incluyen contraseñas.

### Paso 2. Registrar el servicio y el job (una sola vez, como administrador)

En PowerShell abierto como administrador:

```powershell
.\scripts\registrar_pgagent.ps1
```

[registrar_pgagent.ps1](../scripts/registrar_pgagent.ps1) toma las credenciales
de `.env`, crea el archivo `pgpass`, registra el servicio `DunnhumbyPgAgent` y
guarda el job con su horario diario de las 2:00 a. m. (hora local). Ambos quedan
deshabilitados: activarlos en pgAdmin (propiedades del job) después de probarlo.

- Si PostgreSQL no es la versión 15, indicar `-PgAgentExecutable` y `-PsqlExecutable`.
- Para otra hora, indicar `-Hora`, por ejemplo `-Hora 3`.
- Si existía el job anterior `Dunnhumby_ETL_cada_2_horas`, se renombra y se le
  reemplaza el horario.

#### Por qué a las 2:00 a. m.

- Es una hora sin uso: nadie consulta el warehouse desde Excel ni carga datos.
- El job tarda unos 20 minutos (3,5 de sincronización y 10 a 15 del warehouse),
  así que termina mucho antes de la jornada y los informes de la mañana ya
  incluyen los datos del día anterior.
- El equipo debe estar encendido a esa hora. Si estaba apagado, pgAgent ejecuta
  el job pendiente cuando el servicio vuelve a iniciar.

### Paso 3. Probar el job

En pgAdmin, abrir **pgAgent Jobs → Dunnhumby_ETL_madrugada**, usar **Run now** y
comprobar en **Statistics** que termine con código 0.

### Paso 4. Habilitar el horario

En las propiedades del job, activar el job y el horario **Diario 02:00 hora
local**. Revisar **Next run**: debe mostrar las 2:00 a. m. del día siguiente.

pgAgent evalúa el horario en la zona horaria del servidor, que puede ser
distinta a la del equipo (por ejemplo GMT). El script convierte la hora local,
por eso en las propiedades del horario la hora marcada puede no ser 02
(en GMT, las 2:00 a. m. de Costa Rica son las 08).

## 4. Ejecutar el job

Una vez habilitado, se ejecuta solo cada madrugada. Para ejecutarlo a mano:

- **pgAdmin:** clic derecho en **pgAgent Jobs → Dunnhumby_ETL_madrugada → Run now**.
- **PowerShell:**

  ```powershell
  .\logs\jobs\pgagent_ejecutar.cmd
  ```

Cualquiera de las dos llama a
[ejecutar_dbt_pgagent.ps1](../scripts/ejecutar_dbt_pgagent.ps1), que:

1. Comprueba que no haya otra ejecución en curso.
2. Ejecuta `dbt build` con target `dev` para llevar a staging los registros
   nuevos, modificados o eliminados en `public` y probar las vistas. Si falla,
   el warehouse no se toca.
3. Ejecuta `dbt build` con target `warehouse` para actualizar dimensiones y
   `fact_sales`, con sus pruebas.
4. Ejecuta `limpiar_dimensiones` para borrar dimensiones que ya no usa ninguna venta.
5. Guarda el log en `logs/jobs/` y el resumen en `ultima_ejecucion.json`.

### Cómo se conservan los IDs

Las tablas del warehouse usan la materialización `cambios`
([incremental_sync.sql](../macros/incremental_sync.sql)). Nunca reemplaza una
tabla ni vuelve a numerar sus IDs, y `--full-refresh` está deshabilitado.

**Dimensiones.** Cada fila se reconoce por su código original (`unique_key`):
`product_id`, `household_id`, `dim_time_id` o, en `dim_promotional_context`, la
combinación de los siete atributos.

| Situación en staging | Qué pasa en la dimensión |
| --- | --- |
| La fila ya existe y no cambió | No se toca. |
| La fila ya existe y cambió algún atributo | Se actualiza y conserva su ID. |
| La fila es nueva | Se inserta con un ID nuevo. |

En `dim_time` el ID es la fecha (AAAAMMDD), así que siempre es el mismo para el
mismo día. En `dim_promotional_context` los siete atributos son la clave: si
cambia uno, es otra combinación y recibe otro ID.

**`fact_sales`.** No tiene un código original único, así que compara las ventas
completas:

1. Las filas idénticas en staging y en el warehouse conservan su
   `sale_detail_id`. Si una fila se repite, se comparan por número de aparición.
2. Las filas que cambiaron se emparejan por su línea (hogar, cesta, producto,
   tienda, día y hora): se actualizan y conservan su `sale_detail_id`.
3. Las filas nuevas se insertan con un `sale_detail_id` nuevo.
4. Las filas que ya no están en staging se borran.

**Limpieza de dimensiones.** Después de la carga, `limpiar_dimensiones`
([cleanup_dimensions.sql](../macros/cleanup_dimensions.sql)) borra las filas que
ya no usa ninguna venta: días y contextos promocionales sin ventas, y productos
y hogares sin ventas que ya no están en `stg_product` o `int_household`. Si una
de esas filas vuelve a aparecer, se inserta con otro ID. Los IDs borrados no se
reutilizan.

## 5. Revisar el resultado

Abrir `logs/jobs/ultima_ejecucion.json`. Debe decir `"estado": "CORRECTO"`.
Si dice `ERROR`, revisar el final del log que indica ese archivo.

## 6. Cambio de credenciales

Actualizar `.env`, repetir el paso 2 de la [instalación](#3-instalación) y
reiniciar el servicio `DunnhumbyPgAgent` cuando no haya una ejecución en curso.
Después, habilitar de nuevo el job (paso 4 de la instalación).

## Referencias

- [Jobs, pasos y horarios de pgAgent](https://www.pgadmin.org/docs/pgadmin4/latest/pgagent_jobs.html).
- [Materializaciones de dbt](https://docs.getdbt.com/guides/create-new-materializations).
