# central-control

This folder is a launcher. A session running here opens **other** Claude Code
sessions in new terminal windows on this machine, and talks to them as peers.

## Launching

Run through `cc.cmd` (or `cc.ps1`) from this directory:

```
cc dirs                                  folders that have had a session before
cc spawn 7 "check the build"             spawn in folder #7 from that list
cc spawn "C:\some\path" "do the thing"   spawn by path
cc list                                  what is spawned, and what is alive
cc stop <name>                           end one
cc resume <name> ["message"]             reopen a stopped one, same conversation
```

Always pass `-Parent <your own session name>` when spawning, so the new session
knows who to report back to. Get your own name from `ListAgents` — it names the
current session on the first line.

```
cc spawn 7 "summarise the open TODOs" -Parent central-control -Name todo-sweep
```

## Talking to what you launched

A spawned session comes up with `--remote-control <name>`, so it shows up in
`ListAgents` and answers `SendMessage` under that name. The name is the address:
`cc spawn -Name api` gives you a peer called `api`.

Spawning is not instant — the window opens, then Claude takes a few seconds to
start and register. `cc list` shows the process as soon as it exists; `ListAgents`
shows the peer once it has finished starting.

## Things worth knowing

Read [NOTES.md](NOTES.md) before changing how spawning works. It records the
quoting, trust, environment and Windows Terminal behaviour this depends on,
most of it learned by breaking something first.

- **Trust.** An untrusted folder shows a blocking trust prompt. Trust is
  inherited down the tree, so anything under a root you have already accepted
  starts without one. Outside that tree `spawn` writes the flag
  and warns that the window may still ask once; a folder directly under the home
  directory always asks. Watch the `trust` line in the spawn output.
- **Environment.** The launch script clears this session's own `CLAUDE_*`
  variables before starting the new one; without that the child inherits this
  session's id and messaging pipe.
- **Generated launch scripts** live in `%LOCALAPPDATA%\central-control\launch`,
  not in this folder — Windows Terminal loses quoting on the command line it
  forwards, so that path must not contain spaces, and this project's does.
- **State** is in `.state\`: `sessions.json` (what was spawned),
  `known-dirs.json` (every folder ever seen, with a first-seen date), and
  `dirs-index.json` (the numbering `cc dirs` last printed).
