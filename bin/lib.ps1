# central-control :: shared helpers
# Dot-sourced by the scripts in this folder. Not meant to be run directly.

$ErrorActionPreference = 'Stop'

$script:CCBin    = $PSScriptRoot
$script:CCRoot   = Split-Path -Parent $PSScriptRoot
$script:CCState  = Join-Path $script:CCRoot '.state'
$script:CCStore  = Join-Path $script:CCState 'sessions.json'
# Launch scripts live outside the project on purpose: Windows Terminal re-parses
# the command line it is given and loses quoting, so the path handed to it must
# contain no spaces -- which this project's own path does.
$script:CCLaunch = Join-Path (Join-Path $env:LOCALAPPDATA 'central-control') 'launch'

# Environment variables Claude Code sets for the *current* session. A spawned
# session must not inherit them, or it will reuse this session's id / messaging
# pipe and announce itself as a child agent instead of a peer.
$script:CCScrubEnv = @(
    'CLAUDECODE'
    'CLAUDE_CODE_SESSION_ID'
    'CLAUDE_CODE_CHILD_SESSION'
    'CLAUDE_CODE_MESSAGING_SOCKET'
    'CLAUDE_CODE_MESSAGING_TOKEN'
    'CLAUDE_CODE_ENTRYPOINT'
    'CLAUDE_CODE_SESSION_ATTENDED'
    'CLAUDE_CODE_EXECPATH'
    'CLAUDE_CODE_SSE_PORT'
    'CLAUDE_CODE_ORIGINAL_CWD'
    'CLAUDE_PROJECT_DIR'
    'CLAUDE_PID'
    'CLAUDE_EFFORT'
    'AI_AGENT'
)

function Initialize-CCState {
    foreach ($d in @($script:CCState, $script:CCLaunch)) {
        if (-not (Test-Path -LiteralPath $d)) {
            New-Item -ItemType Directory -Path $d -Force | Out-Null
        }
    }
}

# --- registry -------------------------------------------------------------

# PS 5.1's ConvertFrom-Json emits a JSON array as one object instead of
# streaming its elements, so `@(... | ConvertFrom-Json)` yields a one-element
# array holding the real array. Assign first, then wrap.
function Read-CCJsonArray {
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return }
    try { $parsed = ConvertFrom-Json -InputObject $Text } catch { return }
    if ($null -eq $parsed) { return }
    foreach ($item in @($parsed)) { $item }
}

function Read-CCJsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Read-CCJsonArray (Get-Content -LiteralPath $Path -Raw -Encoding UTF8)
}

function Get-CCSessions {
    Initialize-CCState
    @(Read-CCJsonFile -Path $script:CCStore)
}

function Save-CCJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyCollection()][object[]]$Items
    )
    $rows = @($Items)
    if ($rows.Count -eq 0) {
        $json = '[]'
    } else {
        $json = ConvertTo-Json -InputObject $rows -Depth 8
        # PS 5.1 unwraps a one-element array into a bare object.
        if ($rows.Count -eq 1 -and $json.TrimStart()[0] -ne '[') { $json = "[$json]" }
    }
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Save-CCSessions {
    param([AllowEmptyCollection()][object[]]$Sessions)
    Initialize-CCState
    Save-CCJson -Path $script:CCStore -Items $Sessions
}

# `cc dirs` numbers the folders it prints and saves that numbering, so a spawn
# can name a folder by its number instead of its path.
function Resolve-CCIndex {
    param([Parameter(Mandatory = $true)][int]$Number)
    $path = Join-Path $script:CCState 'dirs-index.json'
    if (-not (Test-Path -LiteralPath $path)) {
        throw "No folder list to pick #$Number from. Run 'cc dirs' first."
    }
    $rows = @(Read-CCJsonFile -Path $path)
    $hit = @($rows | Where-Object { [int]$_.N -eq $Number })[0]
    if (-not $hit) {
        throw "The current folder list has no #$Number (it has $($rows.Count) entries). Run 'cc dirs'."
    }
    return $hit.Directory
}

# Read-modify-write the registry under a machine-local mutex so two concurrent
# spawns cannot lose each other's entry.
function Invoke-CCWithRegistry {
    param([Parameter(Mandatory = $true)][scriptblock]$Action)
    $mutex = New-Object System.Threading.Mutex($false, 'Local\central-control-sessions')
    $held = $false
    try {
        $held = $mutex.WaitOne(10000)
        return & $Action
    } finally {
        if ($held) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}

# --- naming ---------------------------------------------------------------

function ConvertTo-CCSlug {
    param([string]$Text)
    $s = $Text -replace '[^A-Za-z0-9._-]', '-'
    $s = $s -replace '-{2,}', '-'
    $s = $s.Trim('-', '.')
    return $s.ToLowerInvariant()
}

function New-CCName {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [string]$Requested
    )
    if ($Requested) {
        $slug = ConvertTo-CCSlug $Requested
        if (-not $slug) { throw "Session name '$Requested' contains no usable characters." }
        if (Get-CCLiveSession -Name $slug) {
            throw "A live session named '$slug' already exists. Pick another -Name, or stop it first (cc stop $slug)."
        }
        return $slug
    }
    $base = ConvertTo-CCSlug (Split-Path -Leaf $Directory)
    if (-not $base) { $base = 'claude' }
    if ($base.Length -gt 24) { $base = $base.Substring(0, 24).Trim('-', '.') }
    for ($i = 0; $i -lt 50; $i++) {
        $suffix = '{0:x4}' -f (Get-Random -Minimum 0 -Maximum 65536)
        $candidate = "$base-$suffix"
        if (-not (Get-CCLiveSession -Name $candidate)) { return $candidate }
    }
    throw "Could not generate a free session name for '$base'."
}

# --- process lookup -------------------------------------------------------

# A spawned session is identified on the command line by its --session-id, which
# is unique per spawn. Resolving the pid on demand keeps the registry honest for
# both terminal backends (Windows Terminal detaches, so its pid is useless).
function Get-CCSessionPid {
    param([Parameter(Mandatory = $true)][string]$SessionId)
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" -ErrorAction SilentlyContinue)
    foreach ($p in $procs) {
        if ($p.CommandLine -and $p.CommandLine.Contains($SessionId)) { return [int]$p.ProcessId }
    }
    return 0
}

function Get-CCLiveSession {
    param([Parameter(Mandatory = $true)][string]$Name)
    foreach ($s in Get-CCSessions) {
        if ($s.name -eq $Name -and (Get-CCSessionPid -SessionId $s.sessionId) -ne 0) { return $s }
    }
    return $null
}

# --- argument quoting -----------------------------------------------------

# Quote one argument for a line inside a .cmd file: MSVCRT backslash/quote rules
# first, then double '%' so cmd.exe does not try to expand it.
function ConvertTo-CCBatchArg {
    param([string]$Value)
    if ($null -eq $Value) { $Value = '' }
    $v = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
    $v = [regex]::Replace($v, '(\\+)$', '$1$1')
    $v = $v -replace '%', '%%'
    return '"' + $v + '"'
}

# --- workspace trust ------------------------------------------------------

# Claude Code shows a blocking "do you trust this folder?" dialog the first time
# it opens a directory, which would strand an unattended window. Pre-accept it.
function Grant-CCTrust {
    param([Parameter(Mandatory = $true)][string]$Directory)
    $py = Get-Command python -ErrorAction SilentlyContinue
    if (-not $py) { return 'skipped (python not found)' }
    $script = Join-Path $script:CCBin 'trust_dir.py'
    $out = & $py.Source $script $Directory 2>&1
    if ($LASTEXITCODE -ne 0) { return "failed ($out)" }
    return ($out | Select-Object -Last 1).ToString()
}

# --- misc -----------------------------------------------------------------

# 8.3 short names are the escape hatch for a spacey path; volumes with them
# disabled just get the original back, and the caller falls back to plain cmd.
function Get-CCShortPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $fso = New-Object -ComObject Scripting.FileSystemObject
        $short = $fso.GetFile($Path).ShortPath
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($fso)
        if ($short) { return $short }
    } catch { }
    return $Path
}

function Resolve-CCDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$Create
    )
    # Join-Path would mangle an already-absolute path, and .NET's GetFullPath
    # resolves relative paths against the *process* cwd, not PowerShell's.
    $full = if ([System.IO.Path]::IsPathRooted($Path)) {
        [System.IO.Path]::GetFullPath($Path)
    } else {
        [System.IO.Path]::GetFullPath([System.IO.Path]::Combine((Get-Location).ProviderPath, $Path))
    }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) {
        if ($Create) {
            New-Item -ItemType Directory -Path $full -Force | Out-Null
        } else {
            throw "Directory not found: $full  (pass -Create to make it)"
        }
    }
    return (Get-Item -LiteralPath $full).FullName
}

function Get-CCParentName {
    param([string]$Explicit)
    if ($Explicit) { return $Explicit }
    if ($env:CC_PARENT_NAME) { return $env:CC_PARENT_NAME }
    return ''
}
