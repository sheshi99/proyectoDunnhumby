-- Ejecutar en Data_warehouse: configura la lectura de dunnhumby_etl usando dblink.
-- Se ejecuta con psql y requiere las variables de entorno del archivo .env.


\set ON_ERROR_STOP on
\getenv pg_host DBT_PG_HOST
\getenv pg_port DBT_PG_PORT
\getenv pg_database DBT_PG_DBNAME
\getenv pg_user DBT_PG_USER
\getenv pg_password DBT_ENV_SECRET_PG_PASSWORD

BEGIN;
DO $$ BEGIN
    IF current_database() <> 'Data_warehouse' THEN
        RAISE EXCEPTION 'Ejecutar conectado a Data_warehouse';
    END IF;
END $$;

CREATE EXTENSION IF NOT EXISTS dblink WITH SCHEMA public;
CREATE SERVER IF NOT EXISTS dunnhumby_etl_server
    FOREIGN DATA WRAPPER dblink_fdw
    OPTIONS (host :'pg_host', port :'pg_port', dbname :'pg_database');
ALTER SERVER dunnhumby_etl_server
    OPTIONS (SET host :'pg_host', SET port :'pg_port', SET dbname :'pg_database');
CREATE USER MAPPING IF NOT EXISTS FOR CURRENT_USER SERVER dunnhumby_etl_server
    OPTIONS (user :'pg_user', password :'pg_password');
ALTER USER MAPPING FOR CURRENT_USER SERVER dunnhumby_etl_server
    OPTIONS (SET user :'pg_user', SET password :'pg_password');
COMMIT;
