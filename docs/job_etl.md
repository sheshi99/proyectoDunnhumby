# Ejecución del job ETL

El job `Dunnhumby_ETL_madrugada` se ejecuta todos los días a las 2:00 a. m.;
sincroniza staging con `public` y actualiza
`Data_warehouse` desde staging.
Usa tres ejecutables de la carpeta `scripts/`. Todos los comandos se ejecutan en
PowerShell desde la carpeta del proyecto.

## Paso 1. Preparar (una sola vez)

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\preparar_pgagent.ps1
```

[preparar_pgagent.ps1](../scripts/preparar_pgagent.ps1) prueba las conexiones de
dbt y crea en `logs/jobs/` los archivos `pgagent_ejecutar.cmd` y
`pgagent_comprobar.cmd`, que son los que llama pgAgent.

## Paso 2. Registrar el job (una sola vez, como administrador)

```powershell
.\scripts\registrar_pgagent.ps1
```

[registrar_pgagent.ps1](../scripts/registrar_pgagent.ps1) crea el servicio
`DunnhumbyPgAgent` y el job con su horario diario de las 2:00 a. m. Ambos quedan
deshabilitados: activarlos en pgAdmin (propiedades del job) después de probarlo.

### Por qué a las 2:00 a. m.

- Es una hora sin uso: nadie consulta el warehouse desde Excel ni carga datos.
- El job tarda unos 20 minutos (3,5 de sincronización y 10 a 15 del warehouse),
  así que termina mucho antes de la jornada y los informes de la mañana ya
  incluyen los datos del día anterior.
- El equipo debe estar encendido a esa hora. Si estaba apagado, pgAgent ejecuta
  el job pendiente cuando el servicio vuelve a iniciar.

## Paso 3. Ejecutar el job

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

## Paso 4. Revisar el resultado

Abrir `logs/jobs/ultima_ejecucion.json`. Debe decir `"estado": "CORRECTO"`.
Si dice `ERROR`, revisar el final del log que indica ese archivo.

Más detalles de la instalación en la [configuración de pgAgent](pgagent.md).
