param(
    [string]$PythonExecutable = (Get-Command python -ErrorAction Stop).Source
)

$ErrorActionPreference = 'Stop'
$jobName = 'Dunnhumby_ETL_cada_2_horas'
$jobDescription = 'Dunnhumby: actualizar staging y construir el warehouse con dbt cada dos horas.'
$jobRoot = Split-Path $PSScriptRoot -Parent
$jobRunner = Join-Path $PSScriptRoot 'ejecutar_job.py'
$jobPython = (Resolve-Path -LiteralPath $PythonExecutable).Path
$jobPowerShell = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$jobUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name

function New-JobAction([bool]$CheckOnly) {
    $pythonLiteral = $jobPython.Replace("'", "''")
    $runnerLiteral = $jobRunner.Replace("'", "''")
    $suffix = if ($CheckOnly) { ' --comprobar' } else { '' }
    $body = "& '{0}' '{1}'{2}; exit `$LASTEXITCODE" -f $pythonLiteral, $runnerLiteral, $suffix
    $arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -Command "{0}"' -f $body
    New-ScheduledTaskAction -Execute $jobPowerShell -Argument $arguments -WorkingDirectory $jobRoot
}

# La comprobacion inicial no modifica datos ni reconstruye tablas.
& $jobPython $jobRunner --comprobar
if ($LASTEXITCODE -ne 0) { throw 'La comprobacion inicial del proyecto fallo.' }

$existing = Get-ScheduledTask -TaskName $jobName -ErrorAction SilentlyContinue
if ($existing) {
    if ($existing.Description -ne $jobDescription) {
        throw 'Existe otra tarea con ese nombre; no se reemplaza.'
    }
    if ($existing.State -eq 'Running') {
        throw 'La tarea esta ejecutandose. Esperar antes de reconfigurarla.'
    }
}

$jobPrincipal = New-ScheduledTaskPrincipal -UserId $jobUser -LogonType Interactive -RunLevel Limited
$jobSettings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1 -Minutes 50)
$jobTrigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddHours(2) `
    -RepetitionInterval (New-TimeSpan -Hours 2)
$jobRegistered = $false

try {
    # Primero comprobar el acceso desde el propio Programador de tareas.
    Register-ScheduledTask -TaskName $jobName -Action (New-JobAction $true) `
        -Trigger $jobTrigger -Principal $jobPrincipal -Settings $jobSettings `
        -Description $jobDescription -Force | Out-Null
    $jobRegistered = $true
    $validationStart = Get-Date
    Start-ScheduledTask -TaskName $jobName
    $validated = $false
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        Start-Sleep -Seconds 1
        $task = Get-ScheduledTask -TaskName $jobName
        $info = Get-ScheduledTaskInfo -TaskName $jobName
        if ($info.LastRunTime -ge $validationStart.AddSeconds(-2) -and $task.State -ne 'Running') {
            if ($info.LastTaskResult -ne 0) {
                throw ('La comprobacion programada fallo. Codigo: ' + $info.LastTaskResult)
            }
            $result = Get-ChildItem -LiteralPath (Join-Path $jobRoot 'logs\jobs') -Filter '*.json' |
                Where-Object { $_.Name -ne 'ultima_ejecucion.json' -and $_.LastWriteTime -ge $validationStart.AddSeconds(-2) } |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($result -and (Get-Content -LiteralPath $result.FullName -Raw -Encoding UTF8 | ConvertFrom-Json).estado -eq 'COMPROBADO') {
                $validated = $true
                break
            }
        }
    }
    if (-not $validated) { throw 'No se pudo verificar el acceso desde el Programador de tareas.' }

    # Con el acceso verificado, dejar la accion completa para las siguientes ejecuciones.
    Set-ScheduledTask -TaskName $jobName -Action (New-JobAction $false) -Trigger $jobTrigger | Out-Null
    Enable-ScheduledTask -TaskName $jobName | Out-Null
    $info = Get-ScheduledTaskInfo -TaskName $jobName
    $logDirectory = Join-Path $jobRoot 'logs\jobs'
    Export-ScheduledTask -TaskName $jobName |
        Set-Content -LiteralPath (Join-Path $logDirectory 'tarea_programada.xml') -Encoding UTF8
    Write-Output ('Tarea registrada y comprobada: ' + $jobName)
    Write-Output ('Cuenta de Windows: ' + $jobUser)
    Write-Output ('Proxima ejecucion: ' + $info.NextRunTime.ToString('yyyy-MM-dd HH:mm:ss'))
    Write-Output 'Repeticion: cada dos horas, mientras la cuenta tenga una sesion iniciada.'
} catch {
    if ($jobRegistered) { Disable-ScheduledTask -TaskName $jobName -ErrorAction SilentlyContinue | Out-Null }
    throw
}
