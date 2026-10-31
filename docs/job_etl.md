# Job de actualización del proyecto

El proceso está definido en `scripts/ejecutar_job.py`. Ejecuta el flujo completo
con PostgreSQL y dbt, usando las conexiones de `.env` y `profiles.yml`.

La tarea se llama **`Dunnhumby_ETL_cada_2_horas`** y se administra en el
**Programador de tareas de Windows**. Windows inicia el proceso; PostgreSQL
almacena los datos y dbt sigue siendo la herramienta que construye los modelos.
La tarea coordina las dos bases, no se guarda como una tabla en ninguna de ellas.

## Recorrido de una ejecución

| Orden | Base o conexión | Operación |
| --- | --- | --- |
| 1 | Ambas bases | Comprobar las tablas, dependencias y conexión de lectura `dblink`. |
| 2 | `dunnhumby_etl` | Reemplazar el contenido de las ocho tablas de staging con una instantánea de public. |
| 3 | dbt, target `dev` | Construir las vistas limpias y el contexto promocional, y ejecutar las pruebas de staging. |
| 4 | dbt, target `warehouse` | Construir las cuatro dimensiones y hechos, y ejecutar sus pruebas. |
| 5 | Ambas bases | Comparar conteos, cantidades, ventas y los tres descuentos entre staging y hechos. |

El refresco conserva las tablas y vistas existentes de staging. No vuelve a
ejecutar la carga de CSV ni modifica las tablas originales de public. El contenido
se reemplaza completo, por lo que se reflejan inserciones, modificaciones y
eliminaciones del origen.

Las ocho copias se actualizan en una sola transacción. Si falla esa etapa, se
revierte el refresco. dbt trabaja por modelo: si una transformación falla, pueden
haber terminado otros modelos antes del error. El proceso se detiene y debe
repetirse completo después de corregir la causa.

Un bloqueo de PostgreSQL evita dos ejecuciones simultáneas de este script.
Mientras trabaja el job, no ejecutar manualmente otros comandos dbt que
reconstruyan las mismas tablas ni refrescar staging desde otra sesión.

## Comprobación y ejecución manual

Desde la raíz del proyecto, con el Python que tiene instaladas las dependencias
de `requirements-dbt.txt`, comprobar la configuración sin cambiar datos:

```powershell
python scripts/ejecutar_job.py --comprobar
```

Para ejecutar el flujo completo:

```powershell
python scripts/ejecutar_job.py
```

El script puede ejecutarse desde cualquier carpeta porque obtiene la raíz del
proyecto a partir de su propia ubicación. No necesita ingresar contraseñas en
la terminal: las lee del `.env` local. El usuario PostgreSQL requiere lectura
en public y permisos de actualización en staging, además de los permisos dbt
para crear y reconstruir las tablas del warehouse.

## Resultados y errores

Cada ejecución genera un `.log` con el detalle de las etapas y un `.json` con su
resultado en `logs/jobs/`. Estos archivos están excluidos de Git.

`logs/jobs/ultima_ejecucion.json` resume la última ejecución completa del proceso:

- `CORRECTO`: refresco, modelos, pruebas y comprobación de medidas terminados.
- `ERROR`: una etapa falló; el mensaje y el log indican dónde revisar.

La comprobación sin cambios usa el estado `COMPROBADO`. Si ya hay una ejecución
activa, la nueva solicitud termina con `OMITIDO` y deja que la primera continúe.
Estos dos casos no sustituyen el resumen de la última ejecución completa.

El código de salida es cero al completar el proceso, comprobar la configuración
o saltar una solicitud simultánea. Es distinto de cero cuando ocurre un error.

El equipo debe permanecer encendido, con PostgreSQL disponible y acceso local
a la carpeta del proyecto para realizar las ejecuciones programadas.

## Registrar la tarea cada dos horas

Completar la preparación del README y verificar una ejecución manual correcta
antes de registrar la tarea. Utilizar la cuenta de Windows que trabajará con el
proyecto y el Python que tiene las dependencias instaladas. Si se usa un entorno
virtual, activarlo antes de ejecutar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\registrar_job.ps1 `
    -PythonExecutable (Get-Command python).Source
```

El registro realiza una comprobación inicial y otra lanzada desde el propio
Programador de tareas. Ambas comprueban el acceso sin actualizar datos. Si pasan,
la acción queda configurada para ejecutar el proceso completo cada dos horas,
a partir de dos horas después del registro. El script muestra la próxima fecha.

La tarea utiliza la cuenta que ejecutó el registro, con permisos limitados y sin
guardar una contraseña de Windows. **Esa cuenta debe mantener la sesión iniciada**
para que se ejecute. Bloquear la pantalla conserva la sesión; cerrar sesión
impide la ejecución hasta que se vuelva a iniciar. El equipo encendido por sí
solo no basta. Los procesos se lanzan en segundo plano con la ventana oculta.

Windows evita iniciar otra instancia si la tarea sigue activa. El bloqueo de
PostgreSQL también protege frente a invocaciones manuales simultáneas. Se
establece un máximo de ejecución de una hora y cincuenta minutos. Si se supera
ese límite, revisar el estado de los modelos y volver a ejecutar el flujo completo.

El registro no instala servicios de Windows ni utiliza pgAgent. El archivo
`logs/jobs/tarea_programada.xml` conserva la definición local para revisión;
no contiene credenciales y está excluido de Git junto con los logs.

## Consultar y controlar la tarea

Abrir **Programador de tareas → Biblioteca del Programador de tareas** y buscar
`Dunnhumby_ETL_cada_2_horas`. El Administrador de tareas sirve para ver procesos;
la programación se consulta y modifica en el Programador de tareas.

Para revisar el estado desde PowerShell:

```powershell
Get-ScheduledTask -TaskName 'Dunnhumby_ETL_cada_2_horas' |
    Select-Object TaskName, State

Get-ScheduledTaskInfo -TaskName 'Dunnhumby_ETL_cada_2_horas' |
    Select-Object LastRunTime, LastTaskResult, NextRunTime
```

El resultado cero indica que el proceso terminó sin error; el resumen JSON
permite distinguir una ejecución completa de una comprobación o una omisión.
La prueba realizada al registrar la tarea corresponde a una comprobación de
acceso; el resultado de la carga completa se consulta en `ultima_ejecucion.json`.

Para solicitar una ejecución completa sin esperar al siguiente horario:

```powershell
Start-ScheduledTask -TaskName 'Dunnhumby_ETL_cada_2_horas'
```

Para desactivar futuras ejecuciones:

```powershell
Disable-ScheduledTask -TaskName 'Dunnhumby_ETL_cada_2_horas'
```

Para volver a habilitarlas:

```powershell
Enable-ScheduledTask -TaskName 'Dunnhumby_ETL_cada_2_horas'
```

Deshabilitar la tarea no detiene una ejecución que ya esté trabajando. Si cambia
la ubicación del proyecto o el Python utilizado, volver a ejecutar el registro
cuando la tarea esté detenida. Si el registro falla, la tarea queda deshabilitada
hasta corregir el problema y registrarla nuevamente.
