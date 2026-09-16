# central-control

Open a new terminal window in any folder, start a Claude Code session there with
Remote Control enabled, and keep track of it — so one session can act as the
entry point for all the others on this machine.

## Use

From this folder, in cmd or PowerShell:

```
cc dirs                                   folders that have had a session before
cc spawn 7 "check the build"              start one in folder #7
cc spawn "C:\some\path" "do the thing"    start one by path
cc list                                   what has been spawned, what is alive
cc resume <name> ["message"]              reopen a stopped one, same conversation
cc stop <name>                            end one (the window stays open)
cc autostart -Enable                      bring this session up at logon
cc help
```

`cc` is `cc.cmd`; from PowerShell `.\cc.ps1` works the same. Every argument after
the verb goes straight to the script in `bin\`, so `cc spawn -?` lists every
option.

### Picking a folder from the list

`cc dirs` reads Claude's own records — `~/.claude.json` for every folder Claude
has been opened in, and `~/.claude/projects/` for the transcripts — and prints
the folders that have had a real session, newest first:

```
 N Sessions LastUsed   Folder
 - -------- --------   ------
 1        1 2026-09-15 central-control
 2        1 2026-09-15 paper\GAIN
 3        2 2026-09-15 prosthetic
 ...
```

The numbering is saved, so `cc spawn 3` starts a session in `prosthetic`. By
default the list covers this project's parent folder and everything below it;
`-Root <dir>` moves that, `-AnyRoot` drops the filter, `-Filter <text>` narrows
by path, and `-All` also shows folders Claude has opened but kept no transcript
for.

Each scan is merged into `.state\known-dirs.json`, which keeps a first-seen date
per folder and holds on to folders after Claude itself forgets them.

## Talking to what you launched

Sessions are spawned with `claude --remote-control <name>`, so each one appears
in `ListAgents` and answers `SendMessage` under that name:

```
cc spawn 3 -Name prosthetic-fix -Parent central-control
```

gives you a peer called `prosthetic-fix`. Without `-Name` the name is the folder
plus four hex digits. Pass `-Parent <your session name>` and the new session is
told who launched it and asked to report back there.

## Starting at logon

```
cc autostart -Enable            scheduled task, 60s after logon
cc autostart -Enable -DelaySeconds 120 -Model opus
cc autostart -Enable -Method Startup    a .cmd in the Startup folder instead
cc autostart -Status
cc autostart -Disable
```

`-Enable` registers a per-user scheduled task that runs `bin\spawn.ps1` against
this folder, so the control session comes up in a terminal window with Remote
Control on, named `central-control`. If task registration is blocked it falls
back to the Startup folder on its own.

## What is where

```
cc.cmd, cc.ps1            entry point
NOTES.md                  findings behind the design; read before changing things
bin\spawn.ps1             open a window and start a session
bin\list.ps1              registry, with live/dead status
bin\stop.ps1              end sessions
bin\resume.ps1            reopen a stopped session, same conversation
bin\dirs.ps1              the numbered folder list
bin\autostart.ps1         logon task / Startup shortcut
bin\discover.py           reads Claude's records to find used folders
bin\trust_dir.py          pre-accepts the workspace-trust dialog
bin\lib.ps1               shared helpers
.state\sessions.json      what has been spawned
.state\known-dirs.json    every folder ever seen, with first-seen dates
.state\dirs-index.json    the numbering cc dirs last printed
```

## Notes

The reasoning behind each of these, with the evidence and how to re-check it,
is in [NOTES.md](NOTES.md).

- **Workspace trust.** An untrusted folder shows a blocking trust prompt, which
  would strand an unattended window. Trust is inherited down the tree: the
  OneDrive root is already trusted, so every folder under it — which is
  everything `cc dirs` lists — starts without a prompt. For a folder outside any
  trusted tree, `spawn` writes the flag into `~/.claude.json` (for the folder,
  its real path and its git root, in the shape Claude writes itself) and says
  so, but that does not reliably suppress the dialog, so it warns you the window
  may ask once. A folder directly under your home directory always asks — Claude
  grants home trust per session by design. The `trust` line in the spawn output
  tells you which case you are in. `-NoTrust` skips the config write entirely.
- **Inherited environment.** The generated launch script clears the launching
  session's `CLAUDE_*` variables before starting the new one. Without that the
  new session inherits the old one's session id and messaging socket and comes
  up believing it is a child agent.
- **Launch scripts** are generated into `%LOCALAPPDATA%\central-control\launch`,
  outside this project, because Windows Terminal re-parses the command line it
  forwards and loses quoting — so that path must contain no spaces, and this
  project's path does. Re-running one restarts that session by hand.
- **Terminal.** Windows Terminal is used when present, otherwise a console
  window; force either with `-Terminal wt` or `-Terminal cmd`.
- **Stopping** ends the Claude process and leaves the window open at a prompt in
  the session's folder, so you can restart it there. `-Forget` also drops it
  from the registry.
