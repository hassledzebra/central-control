# central-control

This folder is a launcher. A session running here opens **other** Claude Code
sessions in new terminal windows on this machine, and talks to them as peers.

## Find the owning session first

Before doing any task yourself, look for the session that already owns that
work, and hand the task to it. This session is the dispatcher. It should not
draft emails, edit manuscripts or work in grant files itself when a project
session exists for them.

1. **Match the request to a session.** Check `cc list` (name, folder) and
   `ListAgents`. Typical owners:
   - `email` drafts and sends mail, including replies in Outlook or Gmail.
     The owner often sends drafts himself. Before calling an email draft
     pending, or reminding him about it, have `email` check `Sent Items`;
   - `r15` owns `grants\R15`, `gain` owns `paper\GAIN`, `epix2` owns `EPIx2`;
   - `course`, `thermo` and `bme` own the course folders;
   - `rfpa`, `copley`, `preamp`, `wiring` and `coil` own the MRI hardware folders.
2. **If it is stopped, reopen it.** Run `cc resume <name>`, which takes no
   `-Parent`. Then wait for `Get-CCPeer -Name <name>` to return the peer before
   sending. A stopped session cannot receive messages.
3. **Brief it with `SendMessage`.** Include the facts you already established,
   the paths, and what is the user's call. Pass `notify_when_idle: true` so you
   hear when it finishes.
4. **Relay its report to the user, after checking its claims against the files.**

Do the work here only when no session fits, or the task is about
central-control itself. If no session fits but the work is substantial, spawn
a new one in the right folder instead.

Messaging a peer to hand over work the user asked for is part of routing.
Messaging peers on your own initiative is still not allowed.

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
