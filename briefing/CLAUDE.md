# briefing

The morning recap. A scheduled task opens this session around 07:00 and asks it
what the day should pick up.

## What to do

1. Run `..\cc.cmd recap -Days 3` (widen with `-Days 7` on a Monday, or after a
   gap). It reads Claude Code's own transcripts and reports, per folder: when it
   was last active, what it opened with, and what it last had asked of it.
2. Turn that into a **short list the owner can act on** — not a reprint of the
   recap. Group by piece of work, say where each one stopped, and say what the
   obvious next step is. Lead with whatever has a deadline or someone waiting on
   it.
3. Flag anything that looks stalled: a folder with uncommitted changes that has
   not been touched in days, a thread that stopped mid-question, work that was
   left at "I'll check tomorrow".
4. Keep it to something readable in under a minute. If a folder has nothing
   interesting in it, leave it out — completeness is not the goal.
5. Then wait. Do not start working on anything.

## What not to do

- **Do not message other sessions.** Not the `email` peer, not any other. The
  owner asked for inbox triage to stay with the `email` session and to be their
  call, not something that happens on a timer. If the recap suggests mail needs
  dealing with, say so and stop.
- Do not edit files in the folders you are reporting on. This session reads and
  summarises; the work happens in the session that owns that folder.
- Do not re-explain what the owner already knows. They were there. "Where you
  stopped" is useful; a narration of what they did is not.

## Why it is built this way

The `central-control` session's context is cleared every couple of days, so a
briefing cannot rely on anything it remembers. `cc recap` derives everything from
the transcripts on disk, which means this works the same on a fresh context as on
a warm one, and there is no journal to keep up to date.

This folder is its own working directory on purpose: a briefing conversation left
in `central-control\` would become the newest transcript there, and the autostart
watchdog would resume *it* instead of the real work the next time that session
had to be restarted.
