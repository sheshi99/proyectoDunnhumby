# Instalación de ODBC y conexión del warehouse con Excel

Esta guía explica paso a paso cómo instalar el controlador PostgreSQL ODBC
en Windows, crear una conexión a `Data_warehouse` y cargar las tablas en Excel.
Corresponde al procedimiento realizado con Excel para Microsoft 365 de 64 bits.

## Antes de empezar

Se necesita:

- Excel de escritorio para Windows.
- PostgreSQL encendido y la base `Data_warehouse` preparada.
- El usuario y la contraseña de PostgreSQL.
- Las cuatro dimensiones y `fact_sales` creadas y validadas.

ODBC permite que Excel consulte PostgreSQL. No instala otra base de datos ni
modifica el ETL. La conexión quedará guardada en Windows y las consultas,
en el libro de Excel que se guarde al finalizar.

## 1. Comprobar si Excel es de 32 o 64 bits

1. Abrir **Excel**.
2. Entrar en **Archivo → Cuenta**.
3. Pulsar **Acerca de Excel**.
4. Leer la primera línea de la ventana: indica **32 bits** o **64 bits**.
5. Cerrar esa ventana con **Aceptar**.

**Resultado esperado:** conocer la arquitectura de Excel. En el equipo del
proyecto se comprobó que es **64 bits**. El controlador debe corresponder a
Excel, no solo a la arquitectura de Windows.

## 2. Descargar el controlador oficial

1. Abrir la [carpeta oficial de versiones de psqlODBC](https://www.postgresql.org/ftp/odbc/releases/).
2. Entrar en la versión que se vaya a instalar. Para el procedimiento de este
   proyecto se utilizó [REL-18_00_0005](https://www.postgresql.org/ftp/odbc/releases/REL-18_00_0005/).
3. Descargar el instalador correspondiente:

   | Excel | Archivo |
   | --- | --- |
   | 64 bits, como en este proyecto | `psqlodbc_x64.msi` |
   | 32 bits | `psqlodbc_x86.msi` |

4. Esperar a que termine la descarga.

Para el equipo utilizado en esta guía, elegir **`psqlodbc_x64.msi`**.
Los archivos `.msm` no son el instalador que se utiliza en estos pasos.

## 3. Instalar psqlODBC

1. Abrir el archivo `.msi` descargado.
2. En la bienvenida, pulsar **Next**.
3. Leer y aceptar el acuerdo de licencia para continuar.
4. En **Custom Setup**, comprobar que **ODBC Driver** esté seleccionado
   para instalarse. La documentación es opcional.
5. Mantener la ubicación predeterminada, como `C:\Program Files\psqlODBC\`.
6. Pulsar **Next** y después **Install**.
7. Si Windows solicita autorización para instalar, aceptar para continuar.
8. Esperar a que termine y pulsar **Finish**.

**Resultado esperado:** el controlador PostgreSQL ODBC queda instalado.
No es necesario reinstalar PostgreSQL ni ejecutar los scripts de carga.

## 4. Abrir el administrador ODBC correcto

Para **Excel de 64 bits**:

1. Presionar **Windows + R**.
2. Escribir:

   ```text
   C:\Windows\System32\odbcad32.exe
   ```

3. Presionar **Enter**.
4. Comprobar que el título indique **Administrador de origen de datos ODBC
   (64 bits)**.

Aunque el ejecutable se llama `odbcad32.exe`, esta ruta abre el administrador
de **64 bits**. Para Excel de **32 bits**, la ruta correspondiente es
`C:\Windows\SysWOW64\odbcad32.exe`.

## 5. Crear el origen de datos para Excel

1. En el administrador ODBC, seleccionar **DSN de usuario**.
2. Pulsar **Agregar…**.
3. Seleccionar **PostgreSQL Unicode(x64)** para Excel de 64 bits.
4. Pulsar **Finalizar**.

**DSN** es el nombre de una configuración de conexión. Al crearlo como
**DSN de usuario**, estará disponible para el usuario actual de Windows;
no configura la conexión para otros equipos ni otras cuentas.

Unicode permite trabajar con tildes y otros caracteres del texto del dataset.
Comprobar el controlador elegido en la lista: el título del formulario de
configuración puede resultar confuso. Durante la preparación apareció un
título ANSI aun después de seleccionar Unicode; se verificó en Windows que
`PostgreSQL Unicode(x64)` apuntaba al controlador Unicode `podbc35w.dll`.
No cambiar de controlador basándose únicamente en ese título.

## 6. Completar los datos de conexión

En el formulario, introducir:

| Campo | Valor para la instalación local del proyecto |
| --- | --- |
| **Data Source** | `Dunnhumby_Excel` |
| **Description** | `Warehouse Dunnhumby` |
| **Database** | `Data_warehouse` |
| **Server** | `localhost` |
| **Port** | `5432` |
| **User Name** | El usuario de PostgreSQL; en la prueba se utilizó `postgres`. |
| **Password** | La contraseña local de ese usuario. |
| **SSL Mode** | Para la prueba local se mantuvo `disable`. |

Respetar el nombre **`Data_warehouse`**. `Dunnhumby_Excel` es el nombre de
la conexión, no el nombre de la base de datos.

`localhost` se utiliza cuando Excel y PostgreSQL están en el mismo equipo.
Si la base está en otro servidor, hay que usar su dirección y revisar su
configuración de acceso y SSL; los valores locales no se trasladan sin cambios.

Introducir la contraseña únicamente en el formulario correspondiente. No
copiarla a esta guía ni compartir capturas que la muestren.

## 7. Probar y guardar la conexión

1. Pulsar **Test**.
2. Esperar el mensaje **Connection successful**.
3. Pulsar **Aceptar** para cerrar el mensaje.
4. Pulsar **Save** en el formulario de conexión.
5. Confirmar que aparece `Dunnhumby_Excel` en **DSN de usuario**.
6. Pulsar **Aceptar** para cerrar el administrador ODBC.

**Resultado esperado:** Windows tiene una conexión guardada y probada hacia
`Data_warehouse`. La instalación y configuración de ODBC quedan completas.

Si la prueba falla, revisar servidor, puerto, nombre exacto de la base,
credenciales y que PostgreSQL esté en ejecución antes de continuar.

## 8. Conectarse desde Excel

1. Abrir un libro nuevo en Excel.
2. Ir a **Datos → Obtener datos → De otras fuentes → Desde ODBC**.
3. En **Nombre de origen de datos (DSN)**, seleccionar **Dunnhumby_Excel**.
4. Dejar las opciones avanzadas sin cambios y pulsar **Aceptar**.
5. Si Excel solicita credenciales, seleccionar **Base de datos**, introducir
   el usuario y contraseña de PostgreSQL y pulsar **Conectar**.
6. Esperar a que aparezca el **Navegador**.

**Resultado esperado:** se muestra `ODBC (dsn=Dunnhumby_Excel)` y debajo la
base `Data_warehouse`.

## 9. Elegir las tablas del warehouse

1. Expandir **Data_warehouse**.
2. Expandir el esquema **public**.
3. Marcar **Seleccionar varios elementos**.
4. Seleccionar estas cinco tablas:

   - `dim_household`
   - `dim_product`
   - `dim_time`
   - `dim_promotional_context`
   - `fact_sales`

5. Pulsar la flecha junto a **Cargar** y elegir **Cargar en…**.

No cargar directamente todas las ventas en una hoja: una hoja de Excel admite
1.048.576 filas y la instalación validada tenía 2.595.732 filas en `fact_sales`.

## 10. Cargar al Modelo de datos

En **Importar datos**:

1. Seleccionar **Crear únicamente la conexión**.
2. Marcar **Agregar estos datos al Modelo de datos**.
3. Pulsar **Aceptar**.
4. Esperar a que terminen las cinco cargas; pueden tardar varios minutos.
5. Revisar el panel **Datos → Consultas y conexiones**.

**Resultado esperado:** las cinco consultas aparecen sin errores y muestran
las filas cargadas. Los datos se guardan en el Modelo de datos, aunque la
hoja de cálculo permanezca vacía.

En la carga realizada durante esta preparación se observaron:

| Tabla | Filas cargadas |
| --- | ---: |
| `dim_household` | 2.500 |
| `dim_product` | 92.353 |
| `dim_time` | 711 |
| `dim_promotional_context` | 1.165 |
| `fact_sales` | 2.595.732 |

Estos conteos son una referencia de esa carga. Si se actualizan las fuentes,
los conteos pueden cambiar y se deben contrastar con el warehouse actual.

## 11. Guardar y actualizar el libro

1. Ir a **Archivo → Guardar como**.
2. Elegir una ubicación y guardar el libro, por ejemplo, como
   `Analisis_Dunnhumby.xlsx`.
3. Para volver a consultar el warehouse más adelante, abrir el libro y pulsar
   **Datos → Actualizar todo**.

pgAgent actualiza el warehouse cada dos horas, pero eso no actualiza por sí
solo los datos ya importados al libro. **Actualizar todo** vuelve a ejecutar
las consultas de Excel contra PostgreSQL.

Con esto queda listo el origen para crear tablas dinámicas desde
**Insertar → Tabla dinámica → Desde el modelo de datos**. Los análisis que
combinan columnas de distintas tablas requieren sus relaciones en el Modelo
de datos; cargarlas por ODBC no garantiza que Excel cree esas relaciones.

