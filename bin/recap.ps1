<#
.SYNOPSIS
    What has been worked on lately, and where each thread stopped.

.DESCRIPTION
    Derived from Claude Code's own transcripts, not from a journal kept by hand,
    so it survives this session's context being cleared and cannot go stale.

.EXAMPLE
    cc recap
    cc recap -Days 7 -Limit 20
    cc recap -Json
#>
[CmdletBinding()]
param(
    # How far back to look.
    [int]$Days = 3,

    # How many folders to print.
    [int]$Limit = 12,

    # Skip the per-folder git lookup, which is what makes this slow.
    [switch]$NoGit,

    [switch]$Json
)

. (Join-Path $PSScriptRoot 'lib.ps1')

$py = Get-Command python -ErrorAction SilentlyContinue
if (-not $py) { throw "python was not found on PATH; recap needs it to read the transcripts." }

$argv = @((Join-Path $PSScriptRoot 'recap.py'), '--days', $Days, '--limit', $Limit)
if ($NoGit) { $argv += '--no-git' }
if ($Json)  { $argv += '--json' }

& $py.Source @argv
