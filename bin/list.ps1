<#
.SYNOPSIS
    Show the sessions central-control has spawned, and whether they are alive.
#>
[CmdletBinding()]
param(
    # Drop registry entries whose process is gone.
    [switch]$Prune,
    # Show dead entries too (default hides nothing; this is here for symmetry).
    [switch]$Json
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$rows = foreach ($s in Get-CCSessions) {
    $p = Get-CCSessionPid -SessionId $s.sessionId
    [pscustomobject]@{
        Name      = $s.name
        Status    = if ($p -ne 0) { 'running' } else { 'stopped' }
        Pid       = $p
        Directory = $s.directory
        Model     = $s.model
        SessionId = $s.sessionId
        SpawnedAt = $s.spawnedAt
        Launch    = $s.launch
    }
}
$rows = @($rows)

if ($Prune) {
    $keep = @($rows | Where-Object { $_.Status -eq 'running' } | ForEach-Object { $_.Name })
    Invoke-CCWithRegistry {
        Save-CCSessions -Sessions @(Get-CCSessions | Where-Object { $keep -contains $_.name })
    }
    $dropped = @($rows | Where-Object { $_.Status -ne 'running' })
    Write-Host "pruned $($dropped.Count) stopped session(s)"
    $rows = @($rows | Where-Object { $_.Status -eq 'running' })
}

if ($Json) {
    if ($rows.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject $rows -Depth 5 }
    return
}

if ($rows.Count -eq 0) {
    Write-Host "no sessions spawned yet (bin\spawn.ps1 <directory>)"
    return
}

$rows | Format-Table Name, Status, Pid, Model, Directory -AutoSize
