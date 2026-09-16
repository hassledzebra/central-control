<#
.SYNOPSIS
    A morning recap, opened for you on a schedule.

.DESCRIPTION
    Registers a per-user scheduled task that opens a session in briefing\ each
    morning. That session runs `cc recap` and turns it into a short list of where
    to pick up -- see briefing\CLAUDE.md for what it is told to do.

    It runs in its own folder deliberately. A briefing conversation sitting in
    central-control\ would become the newest transcript there, and the autostart
    watchdog would resume it instead of the real work.

    Nothing here messages another session. Inbox triage belongs to the `email`
    peer and stays the owner's call.

.EXAMPLE
    .\bin\briefing.ps1 -Enable
    .\bin\briefing.ps1 -Enable -At 08:15
    .\bin\briefing.ps1 -Status
    .\bin\briefing.ps1 -Disable
#>
[CmdletBinding(DefaultParameterSetName = 'Status')]
param(
    [Parameter(ParameterSetName = 'Enable', Mandatory = $true)]
    [switch]$Enable,

    [Parameter(ParameterSetName = 'Disable', Mandatory = $true)]
    [switch]$Disable,

    [Parameter(ParameterSetName = 'Status')]
    [switch]$Status,

    # Time of day. Default is a few minutes off the hour on purpose -- every
    # scheduler on the planet fires at :00.
    [Parameter(ParameterSetName = 'Enable')]
    [string]$At = '06:57',

    # Days of the week to run. Omit for every day.
    [Parameter(ParameterSetName = 'Enable')]
    [ValidateSet('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday')]
    [string[]]$DaysOfWeek,

    # How far back the recap looks.
    [Parameter(ParameterSetName = 'Enable')]
    [int]$Days = 3,

    [Parameter(ParameterSetName = 'Enable')]
    [string]$Model = 'opus'
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$TaskName = 'central-control-briefing'
$Name     = 'briefing'
$dir      = Join-Path $script:CCRoot 'briefing'
$spawn    = Join-Path $PSScriptRoot 'spawn.ps1'

$prompt = @(
    "Morning recap. Read CLAUDE.md in this folder, then run '..\cc.cmd recap -Days $Days'."
    "Turn it into a short, actionable list of where to pick up -- grouped by piece of work,"
    "leading with anything that has a deadline or someone waiting on it, and flagging what"
    "looks stalled. Do not reprint the recap, do not start any work, and do not message any"
    "other session. Then wait."
) -join ' '

function Get-CCBriefingArgs {
    @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', "`"$spawn`"",
        '-Directory', "`"$dir`"",
        '-Name', $Name,
        '-Model', $Model,
        '-NoParentContext',
        '-IfNotRunning',
        '-Prompt', "`"$prompt`""
    )
}

function Show-CCBriefingStatus {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        $info = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
        Write-Host "task      registered ($($task.State))" -ForegroundColor Green
        foreach ($t in $task.Triggers) {
            $start = if ($t.StartBoundary) { ([datetime]$t.StartBoundary).ToString('HH:mm') } else { '?' }
            $days  = if ($t.DaysOfWeek) { " on $($t.DaysOfWeek)" } else { ' daily' }
            Write-Host "          $start$days"
        }
        if ($info) {
            if ($info.LastRunTime -gt [datetime]'1900-01-01') {
                Write-Host "          last run $($info.LastRunTime) -> result $($info.LastTaskResult)"
            }
            if ($info.NextRunTime) { Write-Host "          next run $($info.NextRunTime)" }
        }
    } else {
        Write-Host "task      not registered"
    }

    Write-Host "folder    $dir"
    $live = Get-CCPeer -Name $Name
    if ($live) {
        Write-Host "session   '$Name' is open now (pid $($live.pid))" -ForegroundColor Green
    } else {
        Write-Host "session   '$Name' is not open"
    }
}

if ($Enable) {
    if (-not (Test-Path -LiteralPath $dir)) {
        throw "The briefing folder is missing: $dir"
    }

    $when = [datetime]::ParseExact($At, 'HH:mm', $null)
    if ($DaysOfWeek) {
        $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $DaysOfWeek -At $when
    } else {
        $trigger = New-ScheduledTaskTrigger -Daily -At $when
    }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
                  -Argument ((Get-CCBriefingArgs) -join ' ') -WorkingDirectory $script:CCRoot

    # Interactive, or the window opens in session 0 where nobody can read it.
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                     -LogonType Interactive -RunLevel Limited

    # StartWhenAvailable is what makes a machine that was asleep at 06:57 still
    # get its briefing when it wakes up.
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                    -StartWhenAvailable -MultipleInstances IgnoreNew `
                    -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
        -Principal $principal -Settings $settings -Force `
        -Description "Open the central-control morning recap." | Out-Null

    Write-Host "registered '$TaskName' for $At$(if ($DaysOfWeek) { " on $($DaysOfWeek -join ', ')" } else { ' daily' })" -ForegroundColor Green
    Write-Host ""
    Show-CCBriefingStatus
    return
}

if ($Disable) {
    $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "removed '$TaskName'" -ForegroundColor Yellow
    } else {
        Write-Host "briefing was not scheduled"
    }
    return
}

Show-CCBriefingStatus
