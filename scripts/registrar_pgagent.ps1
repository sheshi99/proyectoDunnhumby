# Registra el job, su paso y el horario en PostgreSQL.
# También configura el servicio Windows y protege su archivo de conexión.
# Al volver a ejecutarlo, deja el job y el horario deshabilitados para validarlos.


param(
    [string]$DbtExecutable = (Get-Command dbt -ErrorAction Stop).Source,
    [string]$PgAgentExecutable = 'C:\Program Files\PostgreSQL\15\bin\pgagent.exe',
    [string]$PsqlExecutable = 'C:\Program Files\PostgreSQL\15\bin\psql.exe'
)
# Ejecutar como administrador. Registra el job deshabilitado para validarlo
# desde el servicio antes de habilitar el horario.
$ErrorActionPreference = 'Stop'
$jobRoot = Split-Path $PSScriptRoot -Parent
$jobDotenv = Join-Path (Split-Path $DbtExecutable -Parent) 'dotenv.exe'
$jobConfigJson = & $jobDotenv -f (Join-Path $jobRoot '.env') list --format json
if ($LASTEXITCODE -ne 0) { throw 'No se pudo leer .env.' }
$jobConfig = ($jobConfigJson -join "`n") | ConvertFrom-Json
$jobService = 'DunnhumbyPgAgent'
$jobName = 'Dunnhumby_ETL_cada_2_horas'
$jobDescription = 'Dunnhumby dbt por comparacion; administrado por scripts/registrar_pgagent.ps1'
$jobLogs = Join-Path $jobRoot 'logs\jobs'
$jobPassFile = Join-Path $jobLogs 'pgagent.pgpass'
$jobHost = $jobConfig.DBT_PG_HOST
$jobPort = $jobConfig.DBT_PG_PORT
$jobUser = $jobConfig.DBT_PG_USER
function Convert-PassField([string]$Value) { $Value.Replace('\','\\').Replace(':','\:') }
function Convert-SqlLiteral([string]$Value) { "'" + $Value.Replace("'", "''") + "'" }
function Convert-LibpqField([string]$Value) { "'" + $Value.Replace('\','\\').Replace("'", "\'") + "'" }
New-Item -ItemType Directory -Path $jobLogs -Force | Out-Null
$jobPassLine = (@($jobHost,$jobPort,'postgres',$jobUser,$jobConfig.DBT_ENV_SECRET_PG_PASSWORD) |
    ForEach-Object { Convert-PassField $_ }) -join ':'
[IO.File]::WriteAllText($jobPassFile, $jobPassLine + "`n", (New-Object Text.UTF8Encoding($false)))
$jobWindowsUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
& icacls.exe $jobPassFile /inheritance:r /grant:r 'SYSTEM:(F)' ($jobWindowsUser + ':(F)') | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'No se pudo proteger el archivo pgpass.' }
$previousPassFile = $env:PGPASSFILE
try {
    $env:PGPASSFILE = $jobPassFile
    $jobConnection = 'host={0} port={1} dbname=postgres user={2}' -f (Convert-LibpqField $jobHost), $jobPort, (Convert-LibpqField $jobUser)
    $jobCode = Get-Content -LiteralPath (Join-Path $jobLogs 'pgagent_ejecutar.cmd') -Raw -Encoding ASCII
    $jobSqlName = Convert-SqlLiteral $jobName
    $jobSqlDescription = Convert-SqlLiteral $jobDescription
    $jobSqlCode = Convert-SqlLiteral $jobCode
    $jobSqlHost = Convert-SqlLiteral $env:COMPUTERNAME
    $jobSql = @"
CREATE EXTENSION IF NOT EXISTS pgagent;
BEGIN;
DO `$register`$
DECLARE j integer;
BEGIN
  SELECT jobid INTO j FROM pgagent.pga_job WHERE jobname=$jobSqlName;
  IF j IS NOT NULL THEN
    IF EXISTS(SELECT 1 FROM pgagent.pga_job WHERE jobid=j AND (jobdesc<>$jobSqlDescription OR jobagentid IS NOT NULL)) THEN
      RAISE EXCEPTION 'Job existente ajeno o en ejecucion; no se reemplaza';
    END IF;
    UPDATE pgagent.pga_job SET jobenabled=false WHERE jobid=j;
    DELETE FROM pgagent.pga_schedule WHERE jscjobid=j;
    DELETE FROM pgagent.pga_jobstep WHERE jstjobid=j;
  ELSE
    INSERT INTO pgagent.pga_job(jobjclid,jobname,jobdesc,jobhostagent,jobenabled)
    SELECT jclid,$jobSqlName,$jobSqlDescription,$jobSqlHost,false FROM pgagent.pga_jobclass WHERE jclname='Data Import'
    RETURNING jobid INTO j;
  END IF;
  INSERT INTO pgagent.pga_jobstep(jstjobid,jstname,jstkind,jstcode,jstonerror)
  VALUES(j,'01_dbt_incremental','b',$jobSqlCode,'f');
  INSERT INTO pgagent.pga_schedule(jscjobid,jscname,jscenabled,jscstart,jscminutes,jschours,jscweekdays,jscmonthdays,jscmonths)
  VALUES(j,'Cada dos horas',false,date_trunc('hour',now())+interval '2 hours',
    ARRAY(SELECT i=0 FROM generate_series(0,59) i),
    ARRAY(SELECT i%2=0 FROM generate_series(0,23) i),
    array_fill(true,ARRAY[7]),array_fill(true,ARRAY[32]),array_fill(true,ARRAY[12]));
END `$register`$;
COMMIT;
"@
    # El delimitador SQL usa dolares literales, sin interpolacion PowerShell.
    $jobSql | & $PsqlExecutable -X -w --dbname $jobConnection -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo registrar el job en PostgreSQL.' }
    if (-not (Get-Service -Name $jobService -ErrorAction SilentlyContinue)) {
        # Registro nativo: pgAgent 4.2.2 no informa bien errores de CreateService.
        $jobBinaryPath = '"' + $PgAgentExecutable + '" RUN ' + $jobService + ' ' + $jobConnection
        $jobVirtualCredential = New-Object Management.Automation.PSCredential('NT AUTHORITY\LocalService', (New-Object Security.SecureString))
        New-Service -Name $jobService -BinaryPathName $jobBinaryPath -StartupType Automatic `
            -Credential $jobVirtualCredential -DisplayName 'Dunnhumby pgAgent' | Out-Null
        if (-not (Get-Service -Name $jobService -ErrorAction SilentlyContinue)) { throw 'La instalacion requiere PowerShell como administrador.' }
    }
    Set-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $jobService) `
        -Name ImagePath -Value ('"' + $PgAgentExecutable + '" RUN ' + $jobService + ' ' + $jobConnection)
    # Cuenta LocalService de privilegios limitados; no se utiliza SYSTEM.
    $jobServiceAccount = '*S-1-5-19'
    $jobPythonRoot = Split-Path (Split-Path $DbtExecutable -Parent) -Parent
    foreach ($jobReadDirectory in @($jobPythonRoot, (Join-Path $jobRoot 'scripts'), (Join-Path $jobRoot 'models'), (Join-Path $jobRoot 'macros'))) {
        & icacls.exe $jobReadDirectory /grant ($jobServiceAccount + ':(OI)(CI)(RX)') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo otorgar lectura al servicio.' }
    }
    foreach ($jobReadFile in @($jobRoot, (Join-Path $jobRoot '.env'), (Join-Path $jobRoot 'profiles.yml'), (Join-Path $jobRoot 'dbt_project.yml'), $jobPassFile)) {
        & icacls.exe $jobReadFile /grant ($jobServiceAccount + ':(RX)') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo otorgar acceso al servicio.' }
    }
    foreach ($jobWriteDirectory in @($jobLogs, (Join-Path $jobRoot 'target'), (Join-Path $jobRoot 'logs'))) {
        New-Item -ItemType Directory -Path $jobWriteDirectory -Force | Out-Null
        & icacls.exe $jobWriteDirectory /grant ($jobServiceAccount + ':(OI)(CI)(M)') | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo otorgar escritura al servicio.' }
    }
    New-ItemProperty -LiteralPath ('HKLM:\SYSTEM\CurrentControlSet\Services\' + $jobService) `
        -Name Environment -PropertyType MultiString -Value @('PGPASSFILE=' + $jobPassFile) -Force | Out-Null
    Set-Service -Name $jobService -StartupType Automatic
    Start-Service -Name $jobService
    Write-Output 'Servicio iniciado; job guardado en postgres, deshabilitado para la validacion inicial.'
} finally {
    $env:PGPASSFILE = $previousPassFile
}
