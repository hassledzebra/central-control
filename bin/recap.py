"""What has been worked on lately, and where each thread stopped.

Reads Claude Code's own transcripts under ~/.claude/projects rather than a
journal kept by hand, so it cannot drift out of date and needs nothing
remembered. For each folder touched in the window it reports:

  - when it was last active, and how many conversations it spans
  - what the most recent conversation opened with   (what it was about)
  - what it last had asked of it                    (where to pick up)

A transcript's real directory comes from the "cwd" field inside it; the folder
name under projects/ is the path with ':', '\\', '/' and ' ' all turned into
'-', which is lossy and cannot be reversed.

Usage:  python recap.py [--days N] [--json] [--limit N]
"""

import argparse
import json
import os
import subprocess
import sys
import time

# A prompt that is only a slash command, or Claude Code's own injected plumbing,
# says nothing about what the work was. Drop it and look further in.
NOISE_PREFIXES = (
    "<command-name>",
    "<local-command-stdout>",
    "<system-reminder>",
    "Caveat: The messages below",
    "<cross-session-message",
    "[Request interrupted",
    # A pasted screenshot arrives as a user turn whose text is only the paste
    # banner, which would otherwise be reported as where the work stopped.
    "[Image:",
)


def claude_home():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")


def is_noise(text):
    t = text.strip()
    if not t:
        return True
    if t.startswith(NOISE_PREFIXES):
        return True
    # A bare slash command, e.g. "/rename central-control".
    if t.startswith("/") and len(t) < 80 and "\n" not in t:
        return True
    return False


def user_texts(path):
    """Every real user turn in a transcript, oldest first, as (ts, text)."""
    out = []
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return out
    with fh:
        for line in fh:
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("type") != "user":
                continue
            msg = rec.get("message") or {}
            content = msg.get("content")
            if isinstance(content, list):
                text = " ".join(
                    b.get("text", "")
                    for b in content
                    if isinstance(b, dict) and b.get("type") == "text"
                )
            elif isinstance(content, str):
                text = content
            else:
                continue
            if is_noise(text):
                continue
            out.append((rec.get("timestamp", ""), " ".join(text.split())))
    return out


def transcript_cwd(path, scan=400):
    """The session's real directory, read out of the transcript.

    Not in the first few records: a session opens with a run of metadata
    (last-prompt, custom-title, agent-name, mode, permission-mode,
    bridge-session, attachment) and "cwd" only appears once a real turn is
    written. Reading five lines finds it in old transcripts and misses it in
    every current one, which is why an unresolved path looks like a folder that
    no longer exists.
    """
    try:
        fh = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return None
    with fh:
        for _ in range(scan):
            line = fh.readline()
            if not line:
                break
            try:
                rec = json.loads(line)
            except ValueError:
                continue
            if rec.get("cwd"):
                return rec["cwd"]
    return None


def git_state(directory):
    """Branch, uncommitted file count and last commit, or None if not a repo."""
    def run(*args):
        try:
            res = subprocess.run(
                ["git", "-C", directory] + list(args),
                capture_output=True, text=True, timeout=10,
            )
        except (OSError, subprocess.SubprocessError):
            return None
        return res.stdout.strip() if res.returncode == 0 else None

    branch = run("rev-parse", "--abbrev-ref", "HEAD")
    if branch is None:
        return None
    status = run("status", "--porcelain")
    last = run("log", "-1", "--format=%h %s (%cr)")
    return {
        "branch": branch,
        "dirty": len([l for l in (status or "").splitlines() if l.strip()]),
        "last_commit": last or "",
    }


def collect(days, want_git=True):
    root = os.path.join(claude_home(), "projects")
    cutoff = time.time() - days * 86400
    folders = {}

    if not os.path.isdir(root):
        return []

    for name in os.listdir(root):
        d = os.path.join(root, name)
        if not os.path.isdir(d):
            continue
        for fn in os.listdir(d):
            if not fn.endswith(".jsonl"):
                continue
            full = os.path.join(d, fn)
            try:
                mtime = os.path.getmtime(full)
                size = os.path.getsize(full)
            except OSError:
                continue
            if mtime < cutoff or size == 0:
                continue
            turns = user_texts(full)
            if not turns:
                continue  # a stub: opened, never used
            directory = transcript_cwd(full) or name
            # The briefing session reads this recap every morning; left in, it
            # would report itself as the most recent thing worked on, every day.
            if os.path.basename(os.path.normpath(directory)).lower() == "briefing":
                continue
            key = os.path.normpath(directory).lower()
            rec = folders.setdefault(key, {
                "directory": os.path.normpath(directory),
                "exists": os.path.isdir(directory),
                "conversations": 0,
                "last_active": 0.0,
                "opened_with": "",
                "left_off": "",
                "session_id": "",
            })
            rec["conversations"] += 1
            if mtime > rec["last_active"]:
                rec["last_active"] = mtime
                rec["opened_with"] = turns[0][1]
                rec["left_off"] = turns[-1][1]
                rec["session_id"] = fn[:-6]

    rows = sorted(folders.values(), key=lambda r: -r["last_active"])
    if want_git:
        for r in rows:
            r["git"] = git_state(r["directory"]) if r["exists"] else None
    return rows


def clip(text, n):
    text = text.strip()
    return text if len(text) <= n else text[: n - 1].rstrip() + "…"


def render(rows, days, limit):
    if not rows:
        return "Nothing worked on in the last %d day(s)." % days

    out = ["Worked on in the last %d day(s):" % days, ""]
    for r in rows[:limit]:
        when = time.strftime("%a %d %b %H:%M", time.localtime(r["last_active"]))
        label = os.path.basename(r["directory"]) or r["directory"]
        out.append("  %s   %s" % (when, label))
        out.append("    %s" % r["directory"])
        if r["conversations"] > 1:
            out.append("    %d conversations" % r["conversations"])
        if r.get("git"):
            g = r["git"]
            bits = ["on %s" % g["branch"]]
            if g["dirty"]:
                bits.append("%d uncommitted" % g["dirty"])
            if g["last_commit"]:
                bits.append("last: %s" % g["last_commit"])
            out.append("    git: %s" % ", ".join(bits))
        if not r["exists"]:
            out.append("    (folder is gone)")
        out.append("    opened:  %s" % clip(r["opened_with"], 150))
        out.append("    stopped: %s" % clip(r["left_off"], 150))
        out.append("")
    if len(rows) > limit:
        out.append("  ... and %d more folder(s); raise --limit to see them." % (len(rows) - limit))
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--days", type=int, default=3)
    ap.add_argument("--limit", type=int, default=12)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--no-git", action="store_true")
    args = ap.parse_args()

    rows = collect(args.days, want_git=not args.no_git)
    if args.json:
        json.dump(rows, sys.stdout, indent=1, default=str)
    else:
        sys.stdout.write(render(rows, args.days, args.limit) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
