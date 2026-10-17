# Scripts SQL

Esta carpeta contiene los scripts SQL del proyecto Dunnhumby para PostgreSQL.
Este README permite que Git incluya la carpeta aunque todavía no haya scripts.

## Organización

Guardá los archivos con extensión `.sql` y nombres descriptivos. Si dependen
unos de otros, usá un prefijo numérico para indicar el orden de ejecución.
Por ejemplo, `01_crear_esquemas.sql`, `02_crear_tablas.sql` y
`03_consultas_validacion.sql`. Estos nombres son ejemplos; los scripts
todavía no están creados.

Al inicio de cada script, agregá un comentario con su propósito, los requisitos
para ejecutarlo y si modifica o elimina datos.

## Ejecución

En pgAdmin, seleccioná la base `dunnhumby_etl`, abrí **Query Tool**, cargá el
archivo `.sql`, revisá su contenido y ejecutalo. Si hay dependencias, respetá
el orden indicado por los prefijos y las instrucciones de cada archivo.

También podés ejecutar un archivo desde la raíz del proyecto en PowerShell:

```powershell
psql -h localhost -p 5432 -U postgres -d dunnhumby_etl -v ON_ERROR_STOP=1 -f scripts/sql/nombre_del_script.sql
```

Reemplazá `nombre_del_script.sql` por un archivo existente. El comando requiere
que `psql` esté disponible en el PATH.

## Subir al repositorio

Los archivos de esta carpeta no están excluidos por el `.gitignore` actual.
Para preparar sus cambios y guardarlos en un commit, desde la raíz del proyecto:

```powershell
git add scripts/sql README.md
git commit -m "Agregar carpeta para scripts SQL y documentación"
git push
```

`git push` requiere una rama con remoto configurado. No incluyás contraseñas
ni credenciales dentro de los scripts.
