# Es el archivo que llama pgAgent. Ejecuta los modelos y pruebas dbt; 
# después llama a la limpieza de dimensiones. Evita dos ejecuciones 
# simultáneas y escribe los logs.


param(
    [string]$DbtExecutable = (Get-Command dbt -ErrorAction Stop).Source,
    [switch]$Comprobar
)
$ErrorActionPreference = 'Stop'
# pgAgent guarda stdout en una base UTF-8; Windows PowerShell usa OEM por defecto.
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)
$OutputEncoding = [Console]::OutputEncoding
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'
$env:DBT_USE_COLORS = 'false'
$jobRoot = Split-Path $PSScriptRoot -Parent
$jobDbt = (Resolve-Path -LiteralPath $DbtExecutable).Path
$jobDotenv = Join-Path (Split-Path $jobDbt -Parent) 'dotenv.exe'
$jobLogs = Join-Path $jobRoot 'logs\jobs'
New-Item -ItemType Directory -Path $jobLogs -Force | Out-Null
$jobLog = Join-Path $jobLogs ((Get-Date -Format 'yyyyMMdd_HHmmss') + '_pgagent.log')
$jobResult = [ordered]@{ inicio=(Get-Date).ToString('o'); programador='pgAgent'; modalidad='incremental'; estado='ERROR'; log=$jobLog }
$jobMutex = New-Object Threading.Mutex($false, 'Global\Dunnhumby_dbt_incremental')
$jobLocked = $false
$jobCode = 1
try {
    try { $jobLocked = $jobMutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $jobLocked = $true }
    if (-not $jobLocked) { throw 'Hay otra ejecucion dbt activa.' }
    if (-not (Test-Path -LiteralPath $jobDotenv)) { throw 'Falta dotenv.exe junto a dbt.exe (python-dotenv[cli]).' }
    . {
        function Invoke-JobDbt([string[]]$DbtArguments) {
            & $jobDotenv -f (Join-Path $jobRoot '.env') run -- $jobDbt @DbtArguments --profiles-dir $jobRoot --project-dir $jobRoot 2>&1 |
                Tee-Object -FilePath $jobLog -Append | Write-Output
            if ($LASTEXITCODE -ne 0) { throw ('dbt fallo; revisar ' + $jobLog) }
        }
        if ($Comprobar) {
            Invoke-JobDbt -DbtArguments @('debug','--target','dev')
            Invoke-JobDbt -DbtArguments @('debug','--target','warehouse')
        } else {
            Invoke-JobDbt -DbtArguments @('build','--target','warehouse','--select','path:models/dimensions','path:models/facts')
            Invoke-JobDbt -DbtArguments @('run-operation','limpiar_dimensiones','--target','warehouse')
        }
        $jobCode = 0
    }
} catch {
    $jobResult.error = $_.Exception.Message
    $_.Exception.Message | Tee-Object -FilePath $jobLog -Append | Write-Output
    $_.InvocationInfo.PositionMessage | Tee-Object -FilePath $jobLog -Append | Write-Output
    $_.ScriptStackTrace | Tee-Object -FilePath $jobLog -Append | Write-Output
} finally {
    if ($jobLocked -and -not $Comprobar) {
        $jobResult.estado = if ($jobCode -eq 0) { 'CORRECTO' } else { 'ERROR' }
        $jobResult.fin = (Get-Date).ToString('o')
        $jobResult | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $jobLogs 'ultima_ejecucion.json') -Encoding UTF8
    }
    if ($jobLocked) { $jobMutex.ReleaseMutex() }
    $jobMutex.Dispose()
}
exit $jobCode
