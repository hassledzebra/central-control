# central-control

**Start Claude Code sessions in new terminal windows from one "control" session,
on Windows — and talk to them by name.**

Claude Code sessions on the same machine can already message each other. What
there is no built-in way to do is *create* one: open a terminal somewhere else,
start Claude there, turn Remote Control on, and get a name you can address it
by. This does that, so a single session becomes the entry point for all the
others.

```
cc dirs                              # folders that have had a Claude session before
cc spawn 7 "run the tests and summarise the failures"
```

That opens a window in folder #7, starts Claude with Remote Control on, and
registers it as a peer. From the launching session:

```
ListAgents                           # the new session is listed by name
SendMessage to: "api-3f9c"  "how's it going?"
```

…and the spawned session can message back, unprompted, when it finishes or gets
stuck.

---

## Requirements

- Windows 10/11, PowerShell 5.1 (the built-in one — nothing to install)
- Claude Code on `PATH`, signed in
- Python 3 on `PATH` — used to read Claude's config and find used folders
- Windows Terminal (optional; falls back to a plain console window)

## Install

```
git clone https://github.com/hassledzebra/central-control.git
cd central-control
cc help
```

`cc` is `cc.cmd`; from PowerShell `.\cc.ps1` is the same thing. No build step, no
dependencies to fetch.

## Commands

| | |
|---|---|
| `cc dirs` | folders that have had a Claude session before, numbered |
| `cc spawn <dir\|N> ["prompt"]` | open a window there and start a session |
| `cc list` | what has been spawned, and what is still alive |
| `cc resume <name> ["message"]` | reopen a stopped session on the same conversation |
| `cc stop <name>` | end a session (its window stays open) |
| `cc autostart -Enable` | bring the control session up at logon |

Everything after the verb is passed straight through to the script in `bin\`, so
`cc spawn -?` lists every option.

### Picking a folder from the list

`cc dirs` reads Claude's own records — `~/.claude.json` for every folder Claude
has been opened in, plus the transcripts under `~/.claude/projects/` — and prints
the folders that have had a real session, newest first:

```
 N Sessions LastUsed   Folder
 - -------- --------   ------
 1        4 2026-09-15 central-control
 2        2 2026-09-15 work\api
 3        1 2026-09-14 work\docs-site
 ...
```

The numbering is saved, so `cc spawn 3` starts a session in `work\docs-site`.

By default the list covers this project's parent folder and everything below it.
`-Root <dir>` moves that, `-AnyRoot` drops the filter, `-Filter <text>` narrows
by path, and `-All` also shows folders Claude opened but kept no transcript for.

Each scan is merged into `.state\known-dirs.json`, which records a first-seen
date per folder and keeps folders after Claude itself forgets them.

### Naming and messaging

Sessions are spawned with `claude --remote-control=<name> --name <name>`, so each
appears in `ListAgents` and answers `SendMessage` under that name:

```
cc spawn 2 -Name api-fix -Parent central-control
```

gives you a peer called `api-fix`. Without `-Name`, the name is the folder plus
four hex digits. `-Parent <name>` tells the new session who launched it, and asks
it to report back there when it finishes, gets blocked, or needs a decision.

Spawning is not instant: the window opens, then Claude takes a few seconds to
start and register. `cc list` sees the process immediately; `ListAgents` shows
the peer once it has finished starting.

### Starting at logon

```
cc autostart -Enable                          # scheduled task, 60s after logon
cc autostart -Enable -DelaySeconds 120 -Model opus
cc autostart -Enable -Method Startup          # a .cmd in the Startup folder instead
cc autostart -Status
cc autostart -Disable
```

`-Enable` registers a per-user scheduled task (no admin needed) that runs
`bin\spawn.ps1` against this folder, so the control session comes up in a
terminal window with Remote Control on, named `central-control`. If task
registration is blocked by policy it falls back to the Startup folder on its own.

Verify it without rebooting:

```powershell
Start-ScheduledTask -TaskName central-control
Get-ScheduledTaskInfo -TaskName central-control   # LastTaskResult should be 0
```

## How it works

Each spawn writes a small generated `.cmd` that clears the launching session's
Claude environment, `cd`s to the target folder, and runs `claude` with the right
flags. The terminal is pointed at that script rather than at a long command
line — so quoting is handled once, in one place, instead of being smeared across
`Start-Process`, `wt.exe` and `cmd.exe`.

Every spawn gets a unique `--session-id`, which is how the process is found again
later: `wt.exe` hands off to an existing Windows Terminal process and exits, so
the pid it returns is useless. `cc list` resolves pids on demand by matching that
id against `claude.exe` command lines.

## Layout

```
cc.cmd, cc.ps1            entry point
NOTES.md                  findings behind the design; read before changing things
bin\spawn.ps1             open a window and start a session
bin\list.ps1              registry, with live/dead status
bin\stop.ps1              end sessions
bin\resume.ps1            reopen a stopped session on the same conversation
bin\dirs.ps1              the numbered folder list
bin\autostart.ps1         logon task / Startup shortcut
bin\discover.py           reads Claude's records to find used folders
bin\trust_dir.py          pre-accepts the workspace-trust dialog
bin\lib.ps1               shared helpers
.state\                   runtime state (gitignored)
```

## Notes

The reasoning behind each of these, with the evidence and how to re-check it, is
in [NOTES.md](NOTES.md).

- **Workspace trust.** An untrusted folder shows a blocking trust prompt, which
  would strand an unattended window. Trust is inherited down the directory tree,
  so if your work lives under one root you have already accepted, everything
  under it starts without a prompt. For a folder outside any trusted tree,
  `spawn` writes the flag into `~/.claude.json` and says so, but that does not
  reliably suppress the dialog — it warns you the window may ask once. A folder
  directly under your home directory always asks; Claude grants home trust per
  session by design. The `trust` line in the spawn output tells you which case
  you are in. `-NoTrust` skips the config write entirely.
- **Inherited environment.** The generated launch script clears the launching
  session's `CLAUDE_*` variables. Without that, the new session inherits the old
  one's session id and messaging socket and comes up believing it is a child
  agent rather than a peer.
- **Launch scripts** are generated into `%LOCALAPPDATA%\central-control\launch`,
  outside the project, because Windows Terminal re-parses the command line it
  forwards and loses quoting — so that path must contain no spaces, and a
  project path often does. Re-running one restarts that session by hand.
- **Terminal.** Windows Terminal is used when present, otherwise a console
  window; force either with `-Terminal wt` or `-Terminal cmd`.
- **Stopping** ends the Claude process and leaves the window open at a prompt in
  the session's folder, so you can restart it there. `-Forget` also drops it from
  the registry. Closing the window instead orphans the Claude process — stop it
  by name.
- **Don't keep the clone inside OneDrive or Dropbox.** Syncing a `.git`
  directory can corrupt it if the folder is ever open on two machines at once.

