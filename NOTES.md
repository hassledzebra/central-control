# Notes — why central-control is built the way it is

Findings from building this, most of which cost a failed attempt to discover.
`README.md` says how to use the tool; this says what bit us and how to check
whether it still bites.

Established against **Claude Code 2.1.273**, Windows 11, PowerShell 5.1,
Windows Terminal 1.24. Anything here that reads Claude Code's internals is
version-specific — re-verify after a major update.

---

## 1. `--remote-control <name>` silently ignores the name

`--remote-control [name]` takes an **optional** value, so the CLI parser does not
consume the following token as that value. `--remote-control smoke4` left the
session auto-named `central-control-d7` (folder name + 2 hex) and `smoke4`
became a stray positional argument.

**Fix:** attach the value with `=`, and set the display name too — `--name` is
what `ListAgents` shows peers as.

```
claude "--remote-control=msot-probe" "--name" "msot-probe"
```

**Re-verify:** spawn with `-Name foo`, then read the `from-name=` on the message
the child sends back. It should be `foo`, not `<folder>-xx`.

---

## 2. Workspace trust is inherited down the tree, and cannot be forced

The blocking "do you trust the files in this folder?" dialog is the single
biggest obstacle to unattended launching. What we established:

- The flag is `projects[<dir>].hasTrustDialogAccepted` in `~/.claude.json`.
- The lookup key is **not** the working directory. Decompiled from the binary:

  ```js
  function Kfe(e){ if(etr(e)) return false; return ie().projects?.[e]?.hasTrustDialogAccepted === true }
  function rse(e){ return FB(LS(e) ?? ar(dt(e))) }   // resolve first, then look up
  ```

  `rse` resolves the directory before the lookup — to a git root, otherwise up
  the tree — so trust is **inherited by descendants**.
- Because `C:\Users\zhan1\OneDrive - University of Central Oklahoma` is trusted,
  every folder under it starts with no prompt. That is the whole working set,
  including everything `cc dirs` lists.
- Writing the flag onto a fresh leaf folder outside a trusted tree **does not
  reliably suppress the dialog**. Tested three times (a temp folder, then
  `~\cc-smoke` twice) — the prompt appeared every time even with the flag
  present and readable in the config.
- A session rooted at the home directory can never be pre-accepted; the binary
  says so outright: *"home trust is session-only"*. So a folder directly under
  `C:\Users\zhan1` always asks.

Two things that were tried and did **not** turn out to be the cause: the config
being clobbered by another running session (the entry was still there
afterwards), and the entry being the wrong shape (writing the full project
object Claude writes for itself did not change the outcome either).

**What the tool does now:** `bin\trust_dir.py` reports honestly rather than
promising — `trusted`, `trusted (via <ancestor>)`, `granted (window may still
ask once)`, or `will-prompt (home trust is session-only)` — and `spawn` prints
that on the `trust` line and warns when a prompt is likely. It still writes the
flag (folder, real path, git root) because it is harmless and sometimes right.

**If you want a new tree to launch unattended:** open it once by hand and accept
the dialog, or put it under an already-trusted parent.

---

## 3. Windows Terminal drops quoting on the command line it forwards

`Start-Process wt.exe -ArgumentList @(..., 'cmd.exe', '/k', $pathWithSpaces)`
quotes the path correctly on the way into `wt`, but `wt` re-parses and hands
`cmd.exe` an **unquoted** path:

```
cmd.exe /k C:\Users\zhan1\OneDrive - University of Central Oklahoma\...\smoke-test.cmd
```

cmd then tried to run `C:\Users\zhan1\OneDrive` and left a bare prompt.

**Fix:** generated launch scripts live in `%LOCALAPPDATA%\central-control\launch`
— outside this project, because this project's own path contains spaces. `spawn`
falls back to an 8.3 short name, and then to the plain `cmd` backend, if the
path it must pass ever does contain a space. `wt -d` was dropped entirely; the
launch script `cd /d`s itself.

`;` is also a command separator to `wt`, so paths handed to it must not contain
one.

---

## 4. A spawned session inherits the launcher's Claude identity

A child process started from inside a Claude session inherits these, and will
otherwise reuse this session's id and messaging pipe and come up believing it is
a child agent:

```
CLAUDECODE                      CLAUDE_CODE_SESSION_ATTENDED
CLAUDE_CODE_SESSION_ID          CLAUDE_CODE_EXECPATH
CLAUDE_CODE_CHILD_SESSION       CLAUDE_CODE_SSE_PORT
CLAUDE_CODE_MESSAGING_SOCKET    CLAUDE_CODE_ORIGINAL_CWD
CLAUDE_CODE_MESSAGING_TOKEN     CLAUDE_PROJECT_DIR
CLAUDE_CODE_ENTRYPOINT          CLAUDE_PID, CLAUDE_EFFORT, AI_AGENT
```

The generated `.cmd` clears each one by name before calling `claude`. Clearing
by prefix (`for /f ... in ('set CLAUDE')`) was rejected deliberately: it would
also wipe a legitimately global `CLAUDE_CONFIG_DIR`.

The list is in `$script:CCScrubEnv` in `bin\lib.ps1`. To refresh it, run
`env | grep -i claude` inside a session and diff.

---

## 5. Diagnosing a session that starts but never appears

A spawned session blocked on a pre-conversation dialog looks like this:

| signal | blocked | started properly |
|---|---|---|
| `claude.exe` process | alive | alive |
| `~/.claude/sessions/<pid>.<hash>.key` | written | written |
| `~/.claude/sessions/<pid>.json` | **missing** | present |
| `~/.claude/projects/<mangled>/<session-id>.jsonl` | **missing** | present |
| `ListAgents` | absent | present |

So: **process alive + no transcript = waiting on a dialog**, and the fastest
move is to look at the window, not to keep probing. Screenshotting it does not
work — `SetForegroundWindow` is restricted, so `CopyFromScreen` captures
whatever is actually in front.

Wait for a session to come up with a background poll on the transcript:

```bash
until ls ~/.claude/projects/*/<session-id>.jsonl >/dev/null 2>&1; do sleep 2; done
```

---

## 6. Finding a spawned session's process

`Start-Process` returns a useless pid for the `wt` backend — `wt.exe` hands off
to an existing Windows Terminal process and exits.

**Fix:** every spawn gets a unique `--session-id <guid>`, which lands on the
command line and can be matched later:

```powershell
Get-CimInstance Win32_Process -Filter "Name='claude.exe'" |
  Where-Object { $_.CommandLine.Contains($sessionId) }
```

This is why the registry resolves pids on demand instead of storing them, and
why `-ResumeSessionId` passes the same guid to `--resume` — either way exactly
one guid identifies the process.

---

## 7. Quoting an argument into a generated `.cmd`

MSVCRT backslash/quote rules, then double `%` so cmd does not expand it:

```powershell
$v = [regex]::Replace($Value, '(\\*)"', '$1$1\"')   # escape quotes, double preceding backslashes
$v = [regex]::Replace($v, '(\\+)$', '$1$1')         # double trailing backslashes
$v = $v -replace '%', '%%'                          # cmd would expand %FOO%
return '"' + $v + '"'
```

`^` and `!` need no handling inside double quotes (delayed expansion is off).
Round-trip tested through `cmd /c script.cmd` into a Python argv dump: `plain`,
`has "quotes" inside`, `pct 100% done`, `C:\dir with space\`, and
`amp & pipe | caret ^ paren )` all survive byte-exact.

---

## 8. PowerShell 5.1 traps hit here

- **`ConvertFrom-Json` does not stream array elements.** `@($text | ConvertFrom-Json)`
  yields a *one-element* array containing the real array, so `$row.lastUsed`
  comes back as `Object[]`. Assign first, then enumerate — that is what
  `Read-CCJsonArray` in `bin\lib.ps1` exists for. Symmetrically, `ConvertTo-Json`
  on a one-element array emits a bare object; `Save-CCJson` re-wraps it.
- **A single `[Parameter()]` attribute makes a script advanced**, and advanced
  scripts reject extra arguments instead of collecting them in `$args`. This
  broke the `cc` dispatcher (`A positional parameter cannot be found that
  accepts argument '.'`). `cc.ps1` declares `param([string]$CCVerb = 'help')`
  with no attribute on purpose, so `-Name`, `-Model`, and a bare path survive in
  `$args` to be forwarded.
- **`Join-Path` mangles an already-absolute second argument**, and
  `[System.IO.Path]::GetFullPath` resolves relative paths against the *process*
  cwd, not PowerShell's. `Resolve-CCDirectory` branches on `IsPathRooted`.
- **`-Confirm:$false` does not survive array splatting** (`& $script @args`); it
  arrives as two tokens. `stop.ps1` therefore does not use
  `ConfirmImpact = 'High'`.

---

## 9. Launching a batch file in a new window

`NoDefaultCurrentDirectoryInExePath=1` is set on this machine, so `cmd /c hi.cmd`
with `-WorkingDirectory` set does **not** find the script — it needs `.\hi.cmd`.
A quoted absolute path works regardless and is what the tool uses:

```powershell
Start-Process -FilePath $env:ComSpec -ArgumentList @('/k', "`"$launchScript`"")
```

`/k` leaves the window at a prompt in the session's folder after Claude exits,
so the session can be restarted by hand. `setlocal` is deliberately absent from
the generated script: its implicit `endlocal` would undo the `cd /d`.

**Killing the hosting `cmd.exe` does not kill `claude.exe`** — it orphans it with
no console. Stop the Claude process by name (`cc stop`), not the window.

---

## 10. The logon scheduled task

- `New-ScheduledTaskTrigger -AtLogOn` has no `-Delay` parameter; set the
  property afterwards in ISO 8601 (`$trigger.Delay = 'PT60S'`).
- `-LogonType Interactive` is required, or the task runs where no desktop can
  show the window.
- `-RunLevel Limited` and a per-user principal mean no admin rights are needed.
- Registration succeeded here; `autostart.ps1` still falls back to a Startup
  folder `.cmd` if policy ever blocks it.
- Verify without rebooting: `Start-ScheduledTask -TaskName central-control`,
  then `Get-ScheduledTaskInfo` (`LastTaskResult` 0) and `cc list`.

---

## 11. Where Claude records which folders have been used

`bin\discover.py` merges two sources:

- `~/.claude.json` → `projects{}` — every directory Claude has been opened in.
- `~/.claude/projects/<mangled>/*.jsonl` — one file per session. The folder name
  is the absolute path with every `:`, `\`, `/` and space replaced by `-`, which
  is lossy (`EPIx2\manuscript` and `EPIx2-manuscript` collide), so the real path
  is read back from the `cwd` field inside the transcript when the mangled name
  does not match a known project.

Of 28 transcript folders only 16 held actual `.jsonl` files; the rest were empty
leftovers and are skipped.

---

## 12. Writing these files

**Bash heredocs on this machine corrupt doubled backslashes.** Even with a
quoted delimiter (`<<'EOF'`), `'(\\*)"'` reached disk as `'(\*)"'` — which is
still a valid regex, matching a literal `*`, so it failed *silently* and the
quoting function returned its input unchanged. The damage was inconsistent
within a single heredoc.

Write anything backslash-sensitive with the `Write` tool or a Python script, and
if a heredoc must be used, `grep` the result back before trusting it.
