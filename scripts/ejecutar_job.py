"""Ejecuta el flujo ETL completo, manualmente o desde el Programador de tareas."""

import argparse
import importlib.metadata
import json
import logging
import os
from pathlib import Path
import subprocess
import sys
from datetime import datetime, timedelta, timezone

import psycopg2
from psycopg2 import sql
from dotenv import load_dotenv


ROOT = Path(__file__).resolve().parent.parent
TZ = timezone(timedelta(hours=-6), "America/Costa_Rica")
TABLES = (
    "campaign_desc", "campaign_table", "causal_data", "coupon",
    "coupon_redempt", "hh_demographic", "product", "transaction_data",
)
LOCK_ID = 9112026


def connect(database):
    return psycopg2.connect(
        host=os.environ["DBT_PG_HOST"], port=os.environ["DBT_PG_PORT"],
        user=os.environ["DBT_PG_USER"],
        password=os.environ["DBT_ENV_SECRET_PG_PASSWORD"],
        dbname=database, connect_timeout=10, application_name="dunnhumby_job",
    )


def columns(cursor, schema, table):
    cursor.execute(
        "SELECT a.attname, pg_catalog.format_type(a.atttypid, a.atttypmod) "
        "FROM pg_catalog.pg_attribute a "
        "JOIN pg_catalog.pg_class c ON c.oid=a.attrelid "
        "JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace "
        "WHERE n.nspname=%s AND c.relname=%s AND c.relkind IN ('r', 'p') "
        "AND a.attnum>0 AND NOT a.attisdropped ORDER BY a.attnum", (schema, table),
    )
    return cursor.fetchall()


def check_configuration(connection):
    for filename in (".env", "profiles.yml"):
        if not (ROOT / filename).is_file():
            raise RuntimeError(f"Falta {filename}. Completar la preparación del README.")
    if os.environ["DBT_PG_DBNAME"] != "dunnhumby_etl":
        raise RuntimeError("DBT_PG_DBNAME debe ser dunnhumby_etl.")
    for package in ("dbt-core", "dbt-postgres"):
        importlib.metadata.version(package)
    with connection.cursor() as cursor:
        for table in TABLES:
            original = columns(cursor, "public", table)
            staging = columns(cursor, "staging", table)
            if not original or original != staging:
                raise RuntimeError(f"Falta una tabla o las columnas difieren: {table}.")
    with connect("Data_warehouse") as warehouse:
        with warehouse.cursor() as cursor:
            cursor.execute("SELECT 1 FROM public.dblink('dunnhumby_etl_server', "
                           "'select 1') AS comprobacion(valor integer)")
            if cursor.fetchone() != (1,):
                raise RuntimeError("No funciona la conexión dblink del warehouse.")
    logging.info("Configuración y acceso a ambas bases verificados.")


def refresh_staging(connection):
    # El bloqueo de sesión se mantiene incluso al confirmar esta transacción.
    connection.set_session(isolation_level="REPEATABLE READ", autocommit=False)
    counts = {}
    with connection:
        with connection.cursor() as cursor:
            cursor.execute("SET LOCAL lock_timeout='60s'")
            originals = sql.SQL(", ").join(sql.Identifier("public", t) for t in TABLES)
            destinations = sql.SQL(", ").join(sql.Identifier("staging", t) for t in TABLES)
            cursor.execute(sql.SQL("LOCK TABLE {} IN ACCESS SHARE MODE").format(originals))
            cursor.execute(sql.SQL("LOCK TABLE {} IN ACCESS EXCLUSIVE MODE").format(destinations))
            definitions = {}
            for table in TABLES:
                original = columns(cursor, "public", table)
                if not original or original != columns(cursor, "staging", table):
                    raise RuntimeError(f"Cambió la estructura de {table}; no se refresca staging.")
                definitions[table] = original
            cursor.execute(sql.SQL("TRUNCATE TABLE {} RESTRICT").format(destinations))
            for table in TABLES:
                fields = sql.SQL(", ").join(sql.Identifier(name) for name, _ in definitions[table])
                cursor.execute(sql.SQL("INSERT INTO {} ({}) SELECT {} FROM {}").format(
                    sql.Identifier("staging", table), fields, fields, sql.Identifier("public", table),
                ))
                copied = cursor.rowcount
                cursor.execute(sql.SQL("SELECT count(*) FROM {}").format(sql.Identifier("public", table)))
                if copied != cursor.fetchone()[0]:
                    raise RuntimeError(f"Conteo diferente al copiar {table}.")
                counts[table] = copied
                logging.info("staging.%s: %s filas copiadas.", table, copied)
                cursor.execute(sql.SQL("ANALYZE {}").format(sql.Identifier("staging", table)))
    connection.autocommit = True
    logging.info("Refresco de las ocho tablas confirmado en una sola transacción.")
    return counts


def run_dbt(target, selections, log_file):
    command = [sys.executable, "-m", "dbt.cli.main", "build", "--profiles-dir", str(ROOT),
               "--target", target, "--select", *selections]
    logging.info("Iniciando dbt build, target %s.", target)
    env = os.environ.copy()
    env["PYTHONIOENCODING"] = "utf-8"
    env["DBT_USE_COLORS"] = "false"
    with log_file.open("a", encoding="utf-8") as output:
        result = subprocess.run(command, cwd=ROOT, env=env, stdout=output, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f"dbt falló en {target}, código {result.returncode}. Revisar el log.")
    logging.info("dbt build y pruebas completados, target %s.", target)


def verify_totals(connection):
    with connection.cursor() as cursor:
        cursor.execute("SELECT count(*), sum(quantity), sum(sales_value), sum(retail_discount), "
                       "sum(coupon_discount), sum(coupon_match_discount) FROM staging.stg_transaction_data")
        expected = cursor.fetchone()
    with connect("Data_warehouse") as warehouse:
        warehouse.set_session(readonly=True)
        with warehouse.cursor() as cursor:
            cursor.execute("SELECT count(*), sum(quantity), sum(sales_value), sum(retail_discount), "
                           "sum(coupon_discount), sum(manufacturer_coupon_discount) FROM public.fact_sales")
            actual = cursor.fetchone()
    if actual != expected:
        raise RuntimeError("Las filas o medidas del warehouse no coinciden con staging.")
    logging.info("Conservación de filas, cantidades, ventas y descuentos verificada: %s filas.", actual[0])
    return actual[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--comprobar", action="store_true", help="Verificar configuración sin actualizar datos.")
    args = parser.parse_args()
    load_dotenv(ROOT / ".env")
    directory = ROOT / "logs" / "jobs"
    directory.mkdir(parents=True, exist_ok=True)
    started = datetime.now(TZ)
    identifier = started.strftime("%Y%m%d_%H%M%S") + f"_{os.getpid()}"
    log_file = directory / (identifier + ".log")
    handlers = [logging.FileHandler(log_file, encoding="utf-8")]
    if sys.stdout is not None:
        handlers.append(logging.StreamHandler(sys.stdout))
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", handlers=handlers)
    summary = dict(inicio=started.isoformat(), estado="EN_EJECUCION", log=str(log_file))
    connection = None
    code = 1
    try:
        logging.info("Inicio del job Dunnhumby.")
        connection = connect(os.environ["DBT_PG_DBNAME"])
        connection.autocommit = True
        with connection.cursor() as cursor:
            cursor.execute("SELECT pg_try_advisory_lock(%s)", (LOCK_ID,))
            if not cursor.fetchone()[0]:
                summary["estado"] = "OMITIDO"
                logging.info("Ya hay otra ejecución del job. Se omite esta solicitud.")
                return 0
        check_configuration(connection)
        if args.comprobar:
            summary["estado"] = "COMPROBADO"
        else:
            summary["tablas_staging"] = refresh_staging(connection)
            run_dbt("dev", ["path:models/staging", "path:models/intermediate"], log_file)
            run_dbt("warehouse", ["path:models/dimensions", "path:models/facts"], log_file)
            summary["filas_hechos"] = verify_totals(connection)
            summary["estado"] = "CORRECTO"
        code = 0
        logging.info("Proceso terminado: %s.", summary["estado"])
    except Exception as error:
        summary["estado"] = "ERROR"
        # No registrar contraseñas, parámetros de conexión ni variables del entorno.
        message = error.diag.message_primary if isinstance(error, psycopg2.Error) else str(error)
        summary["error"] = message or type(error).__name__
        logging.error("Proceso detenido: %s", summary["error"])
    finally:
        if connection is not None:
            connection.close()  # Libera el bloqueo de sesión y revierte una transacción fallida.
        summary["fin"] = datetime.now(TZ).isoformat()
        (directory / (identifier + ".json")).write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
        if not args.comprobar and summary["estado"] != "OMITIDO":
            temporary = directory / (identifier + ".tmp")
            temporary.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
            temporary.replace(directory / "ultima_ejecucion.json")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
