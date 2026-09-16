<#
.SYNOPSIS
    List the folders that have had a Claude Code session in them, numbered so
    `cc spawn <number>` can start a session in one.

.DESCRIPTION
    Every scan is merged into .state\known-dirs.json, which keeps a first-seen
    date per folder. Folders stay in that record after Claude forgets them, so
    the list only ever grows.
#>
[CmdletBinding()]
param(
    # Only folders at or below here. Defaults to the parent of this project.
    [string]$Root,

    # No root filter at all.
    [switch]$AnyRoot,

    # Substring match on the path, case-insensitive.
    [string]$Filter,

    # Include folders Claude has merely opened, with no surviving transcript.
    [switch]$All,

    # Include folders that no longer exist on disk.
    [switch]$IncludeMissing,

    [switch]$Json
)

. (Join-Path $PSScriptRoot 'lib.ps1')

Initialize-CCState

$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { throw "python is required for directory discovery but was not found on PATH." }

$raw = & $py.Source (Join-Path $PSScriptRoot 'discover.py')
if ($LASTEXITCODE -ne 0) { throw "discovery failed: $raw" }
$found = @(Read-CCJsonArray ($raw -join "`n"))

# --- merge into the standing record --------------------------------------

$recordPath = Join-Path $script:CCState 'known-dirs.json'
$known = @{}
foreach ($k in @(Read-CCJsonFile -Path $recordPath)) { $known[$k.directory.ToLowerInvariant()] = $k }

$now = (Get-Date).ToString('o')
$merged = @()
foreach ($f in $found) {
    $key = $f.directory.ToLowerInvariant()
    $lastUsed = if ($f.lastUsed) { [System.DateTimeOffset]::FromUnixTimeMilliseconds([long]($f.lastUsed * 1000)).LocalDateTime } else { $null }
    $entry = [ordered]@{
        directory = $f.directory
        sessions  = [int]$f.sessions
        lastUsed  = if ($lastUsed) { $lastUsed.ToString('o') } else { '' }
        exists    = [bool]$f.exists
        trusted   = [bool]$f.trusted
        firstSeen = if ($known.ContainsKey($key)) { $known[$key].firstSeen } else { $now }
    }
    $merged += [pscustomobject]$entry
    $known.Remove($key) | Out-Null
}
# anything Claude has since forgotten stays in the record, marked stale
foreach ($stale in $known.Values) {
    $stale | Add-Member -NotePropertyName stale -NotePropertyValue $true -Force
    $merged += $stale
}
Save-CCJson -Path $recordPath -Items $merged

# --- filter ---------------------------------------------------------------

$rows = @($merged)
if (-not $All)            { $rows = @($rows | Where-Object { $_.sessions -gt 0 }) }
if (-not $IncludeMissing) { $rows = @($rows | Where-Object { $_.exists }) }

if (-not $AnyRoot) {
    if (-not $Root) { $Root = Split-Path -Parent $script:CCRoot }
    $rootFull = (Get-Item -LiteralPath $Root).FullName.TrimEnd('\')
    $rows = @($rows | Where-Object {
        $_.directory -eq $rootFull -or $_.directory.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)
    })
} else {
    $rootFull = ''
}

if ($Filter) {
    $rows = @($rows | Where-Object { $_.directory -like "*$Filter*" })
}

$rows = @($rows | Sort-Object @{ Expression = { if ($_.lastUsed) { [datetime]$_.lastUsed } else { [datetime]::MinValue } }; Descending = $true })

# --- number them, and remember the numbering ------------------------------

$i = 0
$out = foreach ($r in $rows) {
    $i++
    $shown = $r.directory
    if ($rootFull -and $shown.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
        $shown = $shown.Substring($rootFull.Length + 1)
    }
    [pscustomobject]@{
        N         = $i
        Sessions  = $r.sessions
        LastUsed  = if ($r.lastUsed) { ([datetime]$r.lastUsed).ToString('yyyy-MM-dd') } else { '' }
        Folder    = $shown
        Directory = $r.directory
    }
}
$out = @($out)

Save-CCJson -Path (Join-Path $script:CCState 'dirs-index.json') -Items $out

if ($Json) {
    if ($out.Count -eq 0) { '[]' } else { ConvertTo-Json -InputObject $out -Depth 4 }
    return
}

if ($rootFull) { Write-Host "under $rootFull" -ForegroundColor DarkGray }
if ($out.Count -eq 0) {
    Write-Host "nothing matched (try -All, -AnyRoot, or -IncludeMissing)"
    return
}
$out | Format-Table N, Sessions, LastUsed, Folder -AutoSize
Write-Host "cc spawn <N> [prompt]   to start a session in one of these" -ForegroundColor DarkGray
