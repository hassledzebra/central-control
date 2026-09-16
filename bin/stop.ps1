<#
.SYNOPSIS
    Stop a spawned Claude session by peer name.

.DESCRIPTION
    Ends the claude process. The terminal window stays open at a prompt in the
    session's directory, so the window can be reused or the session resumed.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Position = 0)]
    [string[]]$Name,

    [switch]$All,

    # Also remove the entry from the registry.
    [switch]$Forget
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$sessions = @(Get-CCSessions)
if (-not $All) {
    if (-not $Name) { throw "Give one or more session names, or -All." }
    $sessions = @($sessions | Where-Object { $Name -contains $_.name })
    $missing = @($Name | Where-Object { $n = $_; -not ($sessions | Where-Object { $_.name -eq $n }) })
    foreach ($m in $missing) { Write-Warning "no registry entry named '$m'" }
}

$stopped = @()
foreach ($s in $sessions) {
    $p = Get-CCSessionPid -SessionId $s.sessionId
    if ($p -eq 0) {
        Write-Host "  $($s.name) - already stopped"
        continue
    }
    if ($PSCmdlet.ShouldProcess("$($s.name) (pid $p)", 'Stop Claude session')) {
        Stop-Process -Id $p -Force
        Write-Host "  $($s.name) - stopped (pid $p)" -ForegroundColor Yellow
        $stopped += $s.name
    }
}

if ($Forget) {
    $drop = @($sessions | ForEach-Object { $_.name })
    Invoke-CCWithRegistry {
        Save-CCSessions -Sessions @(Get-CCSessions | Where-Object { $drop -notcontains $_.name })
    }
    Write-Host "forgot $($drop.Count) entr(ies)"
}
