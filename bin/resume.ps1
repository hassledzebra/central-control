<#
.SYNOPSIS
    Reopen a previously spawned session in a new window, continuing its
    conversation.

.DESCRIPTION
    Uses the session id recorded at spawn time, so the conversation carries on
    rather than starting fresh. Refuses to act on a session that is still
    running.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Name,

    # Message to submit on resume.
    [Parameter(Position = 1)]
    [string]$Prompt,

    [ValidateSet('auto', 'wt', 'cmd')]
    [string]$Terminal = 'auto'
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$s = @(Get-CCSessions | Where-Object { $_.name -eq $Name })[0]
if (-not $s) { throw "No session named '$Name'. Run bin\list.ps1 to see what is registered." }

$p = Get-CCSessionPid -SessionId $s.sessionId
if ($p -ne 0) { throw "Session '$Name' is still running (pid $p). Stop it first, or just message it." }

$spawn = @{
    Directory       = $s.directory
    Name            = $Name
    Prompt          = $Prompt
    Terminal        = $Terminal
    Parent          = $s.parent
    ResumeSessionId = $s.sessionId
    NoParentContext = $true
}
if ($s.model) { $spawn['Model'] = $s.model }

& (Join-Path $PSScriptRoot 'spawn.ps1') @spawn
