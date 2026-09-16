<#
    central-control -- launch and track Claude Code sessions in new windows.

      cc spawn <dir> [prompt] [-Name x] [-Model opus] [-Effort high] ...
      cc list [-Prune] [-Json]
      cc stop <name> [-Force] [-Forget]      cc stop -All
  cc autostart -Enable|-Disable|-Status
                                    start this control session at logon

Spawning from the directory list:
  cc dirs                           numbers every known folder
  cc spawn 7 "check the build"      spawns in folder #7
      cc resume <name> [prompt]
      cc help

    Every argument after the verb is passed straight through to the matching
    script in bin\, so `cc spawn -?` shows that script's full parameter list.
#>

# No [Parameter()] attribute on purpose: a single attribute would make this an
# advanced script, and advanced scripts reject the extra arguments (-Name, a bare
# directory, ...) that have to survive in $args to be forwarded to the subcommand.
param([string]$CCVerb = 'help')

$ErrorActionPreference = 'Stop'

$map = @{
    spawn  = 'spawn.ps1'
    new    = 'spawn.ps1'
    list   = 'list.ps1'
    ls     = 'list.ps1'
    stop   = 'stop.ps1'
    kill   = 'stop.ps1'
    resume = 'resume.ps1'
    dirs   = 'dirs.ps1'
    where  = 'dirs.ps1'
    autostart = 'autostart.ps1'
}

function Show-CCHelp {
    @'
central-control -- launch Claude Code sessions in new terminal windows.

  cc spawn <directory> [prompt]     open a window there, start claude with
                                    Remote Control on, register it as a peer
  cc dirs [-Root <dir>] [-Filter s] folders that have had a Claude session
                                    before, numbered; spawn takes the number
  cc list [-Prune] [-Json]          what has been spawned, and what is alive
  cc resume <name> [prompt]         reopen a stopped session, same conversation
  cc stop <name> [-Forget]          end a session (window stays open)
  cc stop -All
  cc autostart -Enable|-Disable|-Status
                                    start this control session at logon

Spawning from the directory list:
  cc dirs                           numbers every known folder
  cc spawn 7 "check the build"      spawns in folder #7

Common spawn options:
  -Name <peer-name>      how other sessions address it   (default <folder>-xxxx)
  -Model <alias>         opus | sonnet | haiku | full model id
  -Effort <level>        low | medium | high | xhigh | max
  -PermissionMode <m>    acceptEdits | auto | plan | dontAsk | manual |
                         bypassPermissions
  -AddDir <dirs...>      extra directories the session may touch
  -Parent <name>         name of the launching session, for reporting back
  -Create                create the directory if it is missing
  -Terminal wt|cmd       terminal backend (default: Windows Terminal if present)
  -DryRun                print the launch script instead of running it

  cc spawn -?            full parameter list
'@
}

if ($CCVerb -in @('help', '-h', '--help', '/?', '')) { Show-CCHelp; return }

if (-not $map.ContainsKey($CCVerb)) {
    Write-Error "unknown command '$CCVerb'. Try: cc help"
    exit 1
}

$target = Join-Path (Join-Path $PSScriptRoot 'bin') $map[$CCVerb]
& $target @args
