# Comprueba las conexiones de dbt y genera los comandos Batch que 
# pgAgent puede ejecutar, conservando correctamente las rutas con espacios y tildes.

param(
    [string]$DbtExecutable = (Get-Command dbt -ErrorAction Stop).Source
)
$ErrorActionPreference = 'Stop'
$jobDbt = (Resolve-Path -LiteralPath $DbtExecutable).Path
$jobRunner = Join-Path $PSScriptRoot 'ejecutar_dbt_pgagent.ps1'
$jobDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'logs\jobs'
$jobShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
& $jobShell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $jobRunner -DbtExecutable $jobDbt -Comprobar
if ($LASTEXITCODE -ne 0) { throw 'La comprobacion dbt fallo.' }
$dbtLiteral = $jobDbt.Replace("'", "''")
$runnerLiteral = $jobRunner.Replace("'", "''")
foreach ($mode in @('comprobar', 'ejecutar')) {
    $suffix = if ($mode -eq 'comprobar') { ' -Comprobar' } else { '' }
    # pgAgent 4.2.2 interpreta stdout con la pagina OEM. El detalle Unicode
    # queda en el log local; devolver al agente un resumen ASCII y el codigo real.
    $body = "& '{0}' -DbtExecutable '{1}'{2} 2>&1 | Out-Null; `$jobExit = `$LASTEXITCODE; if (`$null -eq `$jobExit) {{ `$jobExit = 1 }}; Write-Output ('Dunnhumby dbt incremental: exit=' + `$jobExit); exit `$jobExit" -f $runnerLiteral, $dbtLiteral, $suffix
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
    $batch = "@echo off`r`n`"$jobShell`" -NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -EncodedCommand $encoded >nul 2>&1`r`nset `"DBT_EXIT=%ERRORLEVEL%`"`r`necho Dunnhumby dbt incremental: exit=%DBT_EXIT%`r`nexit /b %DBT_EXIT%`r`n"
    Set-Content -LiteralPath (Join-Path $jobDirectory ("pgagent_{0}.cmd" -f $mode)) -Value $batch -Encoding ASCII
}
Write-Output 'Pasos Batch preparados. No ejecutan el antiguo coordinador Python.'
