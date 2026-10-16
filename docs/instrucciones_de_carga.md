# Guía de Ejecución (Carga de Datos)

Pasos en orden para configurar el entorno y cargar la base de datos PostgreSQL localmente en su computadora:

---

### 1. Sincronizar el Repositorio
Abran la terminal y traigan la versión más reciente desde la rama principal:
```bash
git checkout main
git pull
```

---

### 2. Colocar los Archivos de Datos (CSVs)
Como los archivos `.csv` son pesados y están ignorados en Git, deben colocarlos manualmente:
1. Copien todos los archivos `.csv` del dataset de Dunnhumby.
2. Péguenlos dentro de la carpeta local:
   ```text
   proyectoDunnhumby/database/
   ```

---

### 3. Instalar las Librerías de Python
Abran la terminal en Visual Studio Code y ejecuten:
```bash
pip install pandas psycopg2-binary sqlalchemy
```

> ⚠️ **Nota de permisos en Windows:** Si al ejecutar comandos de Python les da un error de permisos o bloqueo del sistema operativo:
> 1. Cierren Visual Studio Code.
> 2. Háganle clic derecho al ícono de **Visual Studio Code** y seleccionen **"Ejecutar como Administrador"**.

---

### 4. Crear la Base de Datos en PostgreSQL
Abran **pgAdmin** o su terminal de PostgreSQL (`psql`) y ejecuten la siguiente consulta para crear la base de datos vacía:
```sql
CREATE DATABASE dunnhumby_etl;
```

---

### 5. Configurar Credenciales y Ejecutar la Carga
1. Abran el archivo `scripts/cargar_bd.py` en VS Code.
2. Modifiquen su usuario y contraseña de PostgreSQL local en la cadena de conexión (si aplica).
3. Corran el script desde la terminal de VS Code:
   ```bash
   python scripts/cargar_bd.py
   ```
4. Ingresen su contraseña de PostgreSQL si la terminal se las solicita.
5. Verifiquen en pgAdmin que las tablas y registros se hayan cargado correctamente en `dunnhumby_etl`.