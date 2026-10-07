#!/usr/bin/env python3
"""Check `synthesis translate_off` / `synthesis translate_on` balance.

z486 wraps its simulation-only blocks ($fatal liveness watchdogs, reference
models, $display tracing) in synthesis pragmas.  A translate_on with no
matching translate_off (or vice versa) puts simulation-only code in front of
Quartus/Vivado: system tasks and the wide `integer` counters then elaborate
into the fit.  A missing translate_off shipped once at the end of z486.sv, so
this is guarded mechanically.

Only real pragma comments are counted: the comment body after `//` (or inside
`/* ... */`) must itself begin with `synthesis translate_off` /
`synthesis translate_on`.  Prose that merely mentions the words (e.g.
`// Reference models for the translate_off equivalence guard`) is ignored.

`*.sv` and `*.svh` sources tracked by git under <root> are scanned.  Build
outputs (tests/obj_dir*, boards/*/build*) and untracked/ignored files are
skipped.

Usage: check_pragmas.py <rtl-dir>
"""

import fnmatch
import re
import subprocess
import sys
from pathlib import Path

PRAGMA_RE = re.compile(r"^\s*synthesis\s+translate_(off|on)\b")

# Build/sim trees that never carry hand-written RTL pragmas.
SKIP_GLOBS = ("tests/obj_dir*", "tests/obj_dir*/**", "boards/*/build*",
              "boards/*/build*/**")


def iter_comments(text):
    """Yield (line, body) for each // or /* */ comment, skipping strings."""
    i = 0
    n = len(text)
    line = 1
    while i < n:
        c = text[i]
        if c == "\n":
            line += 1
            i += 1
        elif c == '"':
            i += 1
            while i < n and text[i] != '"':
                if text[i] == "\\":
                    i += 1
                if i < n and text[i] == "\n":
                    line += 1
                i += 1
            i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "/":
            j = text.find("\n", i)
            if j == -1:
                j = n
            yield line, text[i + 2:j]
            i = j
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            j = text.find("*/", i + 2)
            if j == -1:
                body = text[i + 2:]
                i = n
            else:
                body = text[i + 2:j]
                i = j + 2
            yield line, body
            line += body.count("\n")
        else:
            i += 1


def check_file(path):
    """Return (last_line, errors, off_count, on_count)."""
    text = path.read_text(errors="replace")
    errors = []
    open_line = None
    off_count = on_count = 0
    last_line = 1
    for line, body in iter_comments(text):
        last_line = line
        m = PRAGMA_RE.match(body)
        if not m:
            continue
        kind = m.group(1)
        if kind == "off":
            off_count += 1
            open_line = line
        else:
            on_count += 1
            if open_line is None:
                errors.append(f"{path}:{line}: translate_on without an open "
                              f"translate_off")
            else:
                open_line = None
    if open_line is not None:
        errors.append(f"{path}:{open_line}: translate_off never closed "
                      f"(no translate_on before end of file)")
    if off_count != on_count:
        errors.append(f"{path}: unbalanced pragmas: {off_count} "
                      f"translate_off vs {on_count} translate_on")
    return last_line, errors, off_count, on_count


def find_sources(root):
    """Return sorted repo-relative *.sv/*.svh source paths."""
    files = None
    try:
        out = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z", "--", "*.sv", "*.svh"],
            capture_output=True, text=True, check=True)
        files = [f for f in out.stdout.split("\0") if f]
    except (OSError, subprocess.CalledProcessError):
        files = [str(p.relative_to(root))
                 for p in root.rglob("*")
                 if p.suffix in (".sv", ".svh")]
    keep = []
    for f in files:
        if any(fnmatch.fnmatch(f, g) for g in SKIP_GLOBS):
            continue
        keep.append(f)
    return sorted(set(keep))


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    root = Path(sys.argv[1])
    if not root.is_dir():
        print(f"check_pragmas: not a directory: {root}", file=sys.stderr)
        return 2

    sources = find_sources(root)
    all_errors = []
    total_off = total_on = 0
    files_with_pragmas = 0
    counted = 0
    for rel in sources:
        path = root / rel
        if not path.is_file():
            continue
        counted += 1
        _last, errors, off, on = check_file(path)
        total_off += off
        total_on += on
        if off or on:
            files_with_pragmas += 1
        all_errors.extend(errors)

    for err in all_errors:
        print(f"check_pragmas: FAIL {err}", file=sys.stderr)

    if all_errors:
        print(f"check_pragmas: FAILED ({len(all_errors)} error(s) in "
              f"{len({e.split(':')[0] for e in all_errors})} file(s))",
              file=sys.stderr)
        return 1

    print(f"check_pragmas: OK - {counted} files scanned, {total_off} "
          f"translate_off / {total_on} translate_on pragmas balanced "
          f"across {files_with_pragmas} file(s) with pragmas")
    return 0


if __name__ == "__main__":
    sys.exit(main())
