<#
.SYNOPSIS
    Start the central-control session automatically when you log on.

.DESCRIPTION
    Two ways to do it:

      Task      a Scheduled Task in your own account. Supports a start delay,
                survives being logged out and back in, and is easy to inspect
                in Task Scheduler. This is the default.

      Startup   a .cmd in your Startup folder. No Task Scheduler involved, so
                it still works where task registration is blocked by policy.

    Either way the work is the same: run bin\spawn.ps1 against this project, so
    the control session comes up in a terminal window with Remote Control on
    and registers itself as a peer named "central-control".

.EXAMPLE
    .\bin\autostart.ps1 -Enable
    .\bin\autostart.ps1 -Status
    .\bin\autostart.ps1 -Disable
#>
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Enable', Mandatory = $true)]
    [switch]$Enable,

    [Parameter(ParameterSetName = 'Disable', Mandatory = $true)]
    [switch]$Disable,

    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status,

    [Parameter(ParameterSetName = 'Enable')]
    [ValidateSet('Task', 'Startup')]
    [string]$Method = 'Task',

    # Wait this long after logon before starting, so OneDrive and the network
    # have settled. Task method only.
    [Parameter(ParameterSetName = 'Enable')]
    [int]$DelaySeconds = 60,

    # Peer name for the control session.
    [Parameter(ParameterSetName = 'Enable')]
    [string]$Name = 'central-control',

    [Parameter(ParameterSetName = 'Enable')]
    [string]$Model,

    # Directory the control session opens in. Defaults to this project.
    [Parameter(ParameterSetName = 'Enable')]
    [string]$Directory
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$TaskName    = 'central-control'
$StartupFile = Join-Path ([Environment]::GetFolderPath('Startup')) 'central-control.cmd'

if (-not $Directory) { $Directory = $script:CCRoot }
$spawn = Join-Path $PSScriptRoot 'spawn.ps1'

function Get-CCAutostartArgs {
    $a = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', "`"$spawn`"",
        '-Directory', "`"$Directory`"",
        '-Name', $Name,
        '-NoParentContext'
    )
    if ($Model) { $a += @('-Model', $Model) }
    return $a
}

# --- status ---------------------------------------------------------------

function Show-CCAutostartStatus {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        Write-Host "task      registered ($($task.State))" -ForegroundColor Green
        if ($info -and $info.LastRunTime -gt [datetime]'1900-01-01') {
            Write-Host "          last run $($info.LastRunTime) -> result $($info.LastTaskResult)"
        }
        Write-Host "          $(($task.Actions | Select-Object -First 1).Execute) $(($task.Actions | Select-Object -First 1).Arguments)" -ForegroundColor DarkGray
    } else {
        Write-Host "task      not registered"
    }

    if (Test-Path -LiteralPath $StartupFile) {
        Write-Host "startup   $StartupFile" -ForegroundColor Green
    } else {
        Write-Host "startup   no shortcut"
    }

    $live = Get-CCLiveSession -Name $Name
    if ($live) {
        Write-Host "session   '$Name' is running now" -ForegroundColor Green
    } else {
        Write-Host "session   '$Name' is not running"
    }
}

# --- enable ---------------------------------------------------------------

function Enable-CCAutostartTask {
    $argLine = (Get-CCAutostartArgs) -join ' '
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $argLine -WorkingDirectory $script:CCRoot

    $trigger = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    if ($DelaySeconds -gt 0) {
        # The cmdlet has no -Delay for logon triggers; the property is there.
        $trigger.Delay = "PT$([int]$DelaySeconds)S"
    }

    # Interactive is what makes the terminal window visible on the desktop; a
    # task running in session 0 would start Claude where nobody can see it.
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
        -StartWhenAvailable -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force `
        -Description "Start the central-control Claude Code session at logon." | Out-Null

    Write-Host "registered scheduled task '$TaskName' (logon + ${DelaySeconds}s)" -ForegroundColor Green
}

function Enable-CCAutostartStartup {
    $argLine = (Get-CCAutostartArgs) -join ' '
    $body = @(
        '@echo off'
        'rem central-control autostart -- remove this file to disable'
        "start `"`" powershell.exe $argLine"
    )
    Set-Content -LiteralPath $StartupFile -Value ($body -join "`r`n") -Encoding ASCII
    Write-Host "wrote $StartupFile" -ForegroundColor Green
}

# --- dispatch -------------------------------------------------------------

if ($Enable) {
    $dir = Resolve-CCDirectory -Path $Directory
    $Directory = $dir
    if ($Method -eq 'Task') {
        try {
            Enable-CCAutostartTask
        } catch {
            Write-Warning "could not register the scheduled task: $($_.Exception.Message)"
            Write-Warning "falling back to the Startup folder."
            Enable-CCAutostartStartup
        }
    } else {
        Enable-CCAutostartStartup
    }
    Write-Host ""
    Show-CCAutostartStatus
    return
}

if ($Disable) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "removed scheduled task '$TaskName'" -ForegroundColor Yellow
    }
    if (Test-Path -LiteralPath $StartupFile) {
        Remove-Item -LiteralPath $StartupFile -Force
        Write-Host "removed $StartupFile" -ForegroundColor Yellow
    }
    if (-not $task -and -not (Test-Path -LiteralPath $StartupFile)) {
        Write-Host "autostart was not enabled"
    }
    return
}

Show-CCAutostartStatus
