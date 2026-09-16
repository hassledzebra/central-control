<#
.SYNOPSIS
    Open a new terminal window in a directory and start a Claude Code session
    there with Remote Control enabled.

.DESCRIPTION
    The new session registers itself as a peer on this machine, so the session
    that launched it can address it by name with ListAgents / SendMessage.

.EXAMPLE
    .\bin\spawn.ps1 "C:\work\api" -Name api -Prompt "Read the README and summarise the layout."
#>
[CmdletBinding()]
param(
    # A path, or the number of a folder from the most recent `cc dirs` listing.
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Directory,

    # Opening prompt. The session starts interactively and submits this first.
    [Parameter(Position = 1)]
    [string]$Prompt,

    # Peer name other sessions use to address this one. Defaults to
    # <folder>-<4 hex>.
    [string]$Name,

    [string]$Model,

    [ValidateSet('acceptEdits', 'auto', 'bypassPermissions', 'manual', 'dontAsk', 'plan')]
    [string]$PermissionMode,

    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max')]
    [string]$Effort,

    # Extra directories the session may touch (claude --add-dir).
    [string[]]$AddDir = @(),

    # Anything else to hand to the claude CLI verbatim.
    [string[]]$ClaudeArgs = @(),

    [ValidateSet('auto', 'wt', 'cmd')]
    [string]$Terminal = 'auto',

    # Continue an existing conversation instead of starting one. The id doubles
    # as the command-line marker used to find the process later, so either way
    # exactly one guid ends up on the command line.
    [string]$ResumeSessionId,

    # Name of the launching session, so the child knows who to report back to.
    [string]$Parent,

    [switch]$Create,
    [switch]$NoTrust,
    [switch]$NoRemoteControl,
    [switch]$NoParentContext,
    [switch]$DryRun
)

. (Join-Path $PSScriptRoot 'lib.ps1')

Initialize-CCState

if ($Directory -match '^[0-9]+$') { $Directory = Resolve-CCIndex -Number ([int]$Directory) }
$dir = Resolve-CCDirectory -Path $Directory -Create:$Create
$sessionName = New-CCName -Directory $dir -Requested $Name
$sessionId = if ($ResumeSessionId) { $ResumeSessionId } else { [guid]::NewGuid().ToString() }
$parentName = Get-CCParentName -Explicit $Parent

# --- trust ---------------------------------------------------------------

$trust = 'skipped (-NoTrust)'
if (-not $NoTrust -and -not $DryRun) {
    try { $trust = Grant-CCTrust -Directory $dir } catch { $trust = "failed ($($_.Exception.Message))" }
}

# --- claude arguments ----------------------------------------------------

$claudeArgv = New-Object System.Collections.Generic.List[string]
if (-not $NoRemoteControl) {
    # --remote-control takes an OPTIONAL value, so a space-separated name is not
    # consumed as the value -- it has to be attached with '='. --name is what
    # ListAgents shows peers, so both get set to the same thing.
    $claudeArgv.Add("--remote-control=$sessionName")
    $claudeArgv.Add('--name'); $claudeArgv.Add($sessionName)
}
if ($ResumeSessionId) {
    $claudeArgv.Add('--resume'); $claudeArgv.Add($sessionId)
} else {
    $claudeArgv.Add('--session-id'); $claudeArgv.Add($sessionId)
}
if ($Model)          { $claudeArgv.Add('--model');           $claudeArgv.Add($Model) }
if ($PermissionMode) { $claudeArgv.Add('--permission-mode'); $claudeArgv.Add($PermissionMode) }
if ($Effort)         { $claudeArgv.Add('--effort');          $claudeArgv.Add($Effort) }
foreach ($d in $AddDir) { $claudeArgv.Add('--add-dir'); $claudeArgv.Add($d) }

if (-not $NoParentContext) {
    $lines = @(
        "You were started by central-control, a launcher that opens Claude Code sessions in new terminal windows on this machine.",
        "Your own peer name is `"$sessionName`". Other sessions address you by that name."
    )
    if ($parentName) {
        $lines += "The session that launched you is `"$parentName`". Use ListAgents to see peers and SendMessage to report back to `"$parentName`" when you finish a task, get blocked, or need a decision."
    } else {
        $lines += "Use ListAgents to see peer sessions on this machine and SendMessage to talk to them."
    }
    $claudeArgv.Add('--append-system-prompt')
    $claudeArgv.Add(($lines -join ' '))
}

foreach ($a in $ClaudeArgs) { $claudeArgv.Add($a) }
if ($Prompt) { $claudeArgv.Add($Prompt) }

$claudeLine = 'claude ' + (($claudeArgv | ForEach-Object { ConvertTo-CCBatchArg $_ }) -join ' ')

# --- launch script -------------------------------------------------------

# Everything the new window runs lives in a generated .cmd. Quoting is then done
# once, here, instead of being smeared across Start-Process and wt.exe.
$launchScript = Join-Path $script:CCLaunch "$sessionName.cmd"

$body = New-Object System.Collections.Generic.List[string]
$body.Add('@echo off')
$body.Add("rem central-control launch script for session `"$sessionName`"")
$body.Add("rem generated $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') -- re-run it to restart this session")
$body.Add("title CC: $sessionName")
$body.Add('')
$body.Add('rem drop the launching session''s own Claude Code environment')
foreach ($v in $script:CCScrubEnv) { $body.Add("set `"$v=`"") }
$body.Add('')
$body.Add("set `"CC_SESSION_NAME=$sessionName`"")
if ($parentName) { $body.Add("set `"CC_PARENT_NAME=$parentName`"") }
$body.Add("set `"CC_DIR=$dir`"")
$body.Add('')
$body.Add("cd /d `"$dir`" || goto cc_baddir")
$body.Add('echo.')
$body.Add("echo   central-control  ::  $sessionName")
$body.Add('echo   %CC_DIR%')
$body.Add('echo.')
$body.Add($claudeLine)
$body.Add('goto :eof')
$body.Add('')
$body.Add(':cc_baddir')
$body.Add('echo [central-control] could not enter %CC_DIR%')

if ($DryRun) {
    Write-Host "--- would write $launchScript ---" -ForegroundColor DarkGray
    $body | ForEach-Object { Write-Host $_ }
    Write-Host "--- terminal: $Terminal ---" -ForegroundColor DarkGray
    return
}

Set-Content -LiteralPath $launchScript -Value ($body -join "`r`n") -Encoding ASCII

# --- open the window -----------------------------------------------------

$backend = $Terminal
if ($backend -eq 'auto') {
    $backend = if (Get-Command wt.exe -ErrorAction SilentlyContinue) { 'wt' } else { 'cmd' }
}

$scriptArg = $launchScript
if ($backend -eq 'wt') {
    # wt re-parses its own command line and drops quoting, so the path it
    # forwards to cmd.exe has to be space-free.
    if ($scriptArg -match '\s') { $scriptArg = Get-CCShortPath $scriptArg }
    if ($scriptArg -match '\s') {
        Write-Warning "Windows Terminal cannot be handed a path containing spaces; opening a plain console window instead."
        $backend = 'cmd'
    }
}

if ($backend -eq 'wt') {
    # -w with an unused window name forces a brand new window. The launch script
    # cds to the target itself, so no -d is needed.
    $wtArgs = @('-w', "cc-$sessionName", 'new-tab', '--title', $sessionName,
                'cmd.exe', '/k', $scriptArg)
    Start-Process -FilePath 'wt.exe' -ArgumentList $wtArgs | Out-Null
} else {
    Start-Process -FilePath $env:ComSpec -ArgumentList @('/k', "`"$launchScript`"") | Out-Null
}

# --- register ------------------------------------------------------------

$record = [ordered]@{
    name       = $sessionName
    sessionId  = $sessionId
    directory  = $dir
    terminal   = $backend
    model      = $Model
    prompt     = $Prompt
    parent     = $parentName
    launch     = $launchScript
    spawnedAt  = (Get-Date).ToString('o')
}

Invoke-CCWithRegistry {
    $all = @(Get-CCSessions | Where-Object { $_.name -ne $sessionName })
    Save-CCSessions -Sessions ($all + [pscustomobject]$record)
}

# --- confirm it came up --------------------------------------------------

$pid_ = 0
$deadline = (Get-Date).AddSeconds(25)
while ((Get-Date) -lt $deadline) {
    $pid_ = Get-CCSessionPid -SessionId $sessionId
    if ($pid_ -ne 0) { break }
    Start-Sleep -Milliseconds 400
}

Write-Host ""
Write-Host "  session   $sessionName" -ForegroundColor Green
Write-Host "  directory $dir"
Write-Host "  terminal  $backend"
Write-Host "  trust     $trust"
if ($trust -notlike 'trusted*' -and $trust -notlike 'skipped*') {
    Write-Host "            this folder sits outside any trusted tree, so the new" -ForegroundColor Yellow
    Write-Host "            window may ask you to accept it once before starting." -ForegroundColor Yellow
}
if ($pid_ -ne 0) {
    Write-Host "  status    running (pid $pid_)" -ForegroundColor Green
} else {
    Write-Host "  status    window opened, claude not detected yet" -ForegroundColor Yellow
}
Write-Host ""

[pscustomobject]@{
    Name      = $sessionName
    SessionId = $sessionId
    Directory = $dir
    Terminal  = $backend
    Trust     = $trust
    Pid       = $pid_
    Running   = ($pid_ -ne 0)
}
