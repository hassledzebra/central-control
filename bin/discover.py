"""Find every folder on this machine that has had a Claude Code session in it.

Two sources, merged:

  ~/.claude.json           projects{} -- one key per directory Claude has ever
                           been opened in, whether or not a transcript survived
  ~/.claude/projects/<d>/  the transcripts themselves (*.jsonl, one per
                           session). The folder name is the absolute path with
                           every ':', '\\', '/' and ' ' replaced by '-', which is
                           lossy, so the real path is read back out of the
                           transcript's own "cwd" field where one exists.

Prints a JSON array on stdout:
  [{directory, exists, sessions, lastUsed, inConfig, trusted}, ...]

Usage:  python discover.py
"""

import json
import os
import sys

MANGLE = str.maketrans({":": "-", "\\": "-", "/": "-", " ": "-"})


def claude_home():
    return os.environ.get("CLAUDE_CONFIG_DIR") or os.path.expanduser("~/.claude")


def config_file():
    if os.environ.get("CLAUDE_CONFIG_DIR"):
        return os.path.join(claude_home(), ".claude.json")
    return os.path.expanduser("~/.claude.json")


def read_config():
    path = config_file()
    if not os.path.exists(path):
        return {}
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except (ValueError, OSError):
        return {}


def cwd_from_transcript(jsonl):
    """The first few records of a transcript carry the session's real cwd."""
    try:
        with open(jsonl, encoding="utf-8", errors="replace") as fh:
            for _ in range(5):
                line = fh.readline()
                if not line:
                    break
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                cwd = rec.get("cwd")
                if cwd:
                    return cwd
    except OSError:
        pass
    return None


def scan_transcripts():
    """-> {mangled_name: {'sessions': n, 'lastUsed': epoch, 'cwd': path|None}}"""
    root = os.path.join(claude_home(), "projects")
    out = {}
    if not os.path.isdir(root):
        return out
    for name in os.listdir(root):
        d = os.path.join(root, name)
        if not os.path.isdir(d):
            continue
        files = [f for f in os.listdir(d) if f.endswith(".jsonl")]
        if not files:
            continue
        newest, latest = None, 0.0
        for f in files:
            full = os.path.join(d, f)
            try:
                mt = os.path.getmtime(full)
            except OSError:
                continue
            if mt > latest:
                latest, newest = mt, full
        out[name] = {
            "sessions": len(files),
            "lastUsed": latest,
            "cwd": cwd_from_transcript(newest) if newest else None,
        }
    return out


def main():
    cfg = read_config()
    projects = cfg.get("projects", {}) or {}
    transcripts = scan_transcripts()

    # directory -> record, keyed case-insensitively because Windows paths are
    records = {}

    def slot(directory):
        key = os.path.normpath(directory).lower()
        if key not in records:
            records[key] = {
                "directory": os.path.normpath(directory),
                "exists": os.path.isdir(directory),
                "sessions": 0,
                "lastUsed": 0.0,
                "inConfig": False,
                "trusted": False,
            }
        return records[key]

    for directory, meta in projects.items():
        rec = slot(directory)
        rec["inConfig"] = True
        if isinstance(meta, dict):
            rec["trusted"] = bool(meta.get("hasTrustDialogAccepted"))

    # Match transcripts to config paths by mangled name; fall back to the cwd
    # recorded inside the transcript for anything left over.
    by_mangle = {}
    for directory in projects:
        by_mangle.setdefault(os.path.normpath(directory).translate(MANGLE), directory)

    for name, info in transcripts.items():
        directory = by_mangle.get(name) or info.get("cwd")
        if not directory:
            continue
        rec = slot(directory)
        rec["sessions"] += info["sessions"]
        rec["lastUsed"] = max(rec["lastUsed"], info["lastUsed"])

    rows = sorted(
        records.values(),
        key=lambda r: (-r["lastUsed"], r["directory"].lower()),
    )
    json.dump(rows, sys.stdout, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
