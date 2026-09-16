"""Pre-accept Claude Code's workspace-trust dialog for one directory.

Claude Code blocks on a "do you trust the files in this folder?" prompt the
first time it opens an untrusted directory, which would strand an unattended
window. The flag lives in ~/.claude.json under
projects[<dir>].hasTrustDialogAccepted.

What that flag is keyed on is not the working directory itself. Claude resolves
the directory first -- to its git root, and otherwise up the tree -- so a folder
inside an already-trusted tree inherits that trust, while writing the flag on a
fresh leaf folder whose ancestors are untrusted does not reliably suppress the
prompt. Trust for a session rooted at the home directory is session-only by
design and cannot be pre-accepted at all.

So this reports honestly rather than promising:

  trusted      an ancestor (or this folder) is already trusted -- no prompt
  granted      the flag was written, but the window may still ask once
  will-prompt  nothing here can help; expect the dialog
  failed (..)  could not read or write the config

Usage:  python trust_dir.py <directory>
"""

import copy
import json
import os
import shutil
import sys
import tempfile

KEY = "hasTrustDialogAccepted"

# Claude writes a full project object; a bare {"hasTrustDialogAccepted": true}
# is not the shape it creates for itself.
DEFAULT_PROJECT = {
    "allowedTools": [],
    "mcpContextUris": [],
    "mcpServers": {},
    "enabledMcpjsonServers": [],
    "disabledMcpjsonServers": [],
    "hasTrustDialogAccepted": False,
    "hasClaudeMdExternalIncludesApproved": False,
    "hasClaudeMdExternalIncludesWarningShown": False,
    "exampleFiles": [],
}


def config_path():
    if os.environ.get("CLAUDE_CONFIG_DIR"):
        return os.path.join(os.environ["CLAUDE_CONFIG_DIR"], ".claude.json")
    return os.path.expanduser("~/.claude.json")


def git_root(start):
    cur = os.path.abspath(start)
    while True:
        if os.path.exists(os.path.join(cur, ".git")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return None
        cur = parent


def ancestors(path):
    cur = os.path.abspath(path)
    while True:
        yield cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return
        cur = parent


def trusted_ancestor(projects, target):
    """Nearest self-or-ancestor Claude already trusts, ignoring home."""
    lookup = {os.path.normcase(k): v for k, v in projects.items()}
    home = os.path.normcase(os.path.abspath(os.path.expanduser("~")))
    for cur in ancestors(target):
        key = os.path.normcase(cur)
        if key == home:
            return None  # home trust is session-only; it does not cover children
        entry = lookup.get(key)
        if isinstance(entry, dict) and entry.get(KEY) is True:
            return cur
    return None


def keys_to_write(target):
    """The directory as given, its real path, and its git root."""
    out, seen = [], set()
    candidates = [os.path.abspath(target)]
    try:
        candidates.append(os.path.realpath(target))
    except OSError:
        pass
    root = git_root(target)
    if root:
        candidates.append(root)
    for c in candidates:
        c = os.path.normpath(c)
        if os.path.normcase(c) not in seen:
            seen.add(os.path.normcase(c))
            out.append(c)
    return out


def write_config(path, data):
    shutil.copy2(path, path + ".central-control.bak")
    directory = os.path.dirname(path) or "."
    fd, tmp = tempfile.mkstemp(dir=directory, prefix=".claude.json.", suffix=".tmp")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(data, fh, indent=2, ensure_ascii=False)
        os.replace(tmp, path)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def main(argv):
    if len(argv) != 2:
        print("usage: trust_dir.py <directory>", file=sys.stderr)
        return 2

    target = os.path.abspath(argv[1])
    if not os.path.isdir(target):
        print("failed (not a directory: %s)" % target, file=sys.stderr)
        return 2

    path = config_path()
    if not os.path.exists(path):
        print("failed (no %s)" % path, file=sys.stderr)
        return 1

    try:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
    except (ValueError, OSError) as exc:
        print("failed (%s)" % exc, file=sys.stderr)
        return 1

    projects = data.setdefault("projects", {})

    anc = trusted_ancestor(projects, target)
    if anc:
        print("trusted" if os.path.normcase(anc) == os.path.normcase(target)
              else "trusted (via %s)" % anc)
        return 0

    home = os.path.normcase(os.path.abspath(os.path.expanduser("~")))
    if os.path.normcase(target) == home:
        print("will-prompt (home trust is session-only)")
        return 0

    changed = False
    for key in keys_to_write(target):
        entry = projects.get(key)
        if not isinstance(entry, dict):
            entry = {}
            projects[key] = entry
        before = dict(entry)
        for field, default in DEFAULT_PROJECT.items():
            entry.setdefault(field, copy.deepcopy(default))
        entry[KEY] = True
        if entry != before:
            changed = True

    if changed:
        write_config(path, data)

    print("granted (window may still ask once)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
