#!/usr/bin/env python3
"""Report always_ff state that its reset branch never assigns.

Three live defects of exactly this shape were fixed by hand (i_first,
fault_suppress_delay_slot, any_fault_r); this check makes the next one fail a
test instead of a game.  Findings that are genuinely benign are listed in
ALLOW with the reason, so a new omission is a failure.

Usage: scripts/check_reset_lists.py [--list]
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (file, signal) -> why the omission is safe today.
ALLOW = {
    ("data_unit.sv", "flag2_af_r"): "read only with flag2_eflags_p set",
    ("data_unit.sv", "flag2_cf_r"): "read only with flag2_eflags_p set",
    ("data_unit.sv", "flag2_of_r"): "read only with flag2_eflags_p set",
    ("data_unit.sv", "flag2_result_r"): "read only with flag2_eflags_p set",
    ("data_unit.sv", "flag2_size_r"): "read only with flag2_eflags_p set",
    ("data_unit.sv", "flag2_zsp_r"): "read only with flag2_eflags_p set",
    ("hardwired_control.sv", "commit_sel"): "recipe_state.hardwired powers to 0",
    ("hardwired_control.sv", "hardwired"): "powers to 0 = not a recipe",
    ("hardwired_control.sv", "jcc"): "read only while hardwired",
    ("hardwired_control.sv", "multi_ustep"): "read only while hardwired",
    ("hardwired_control.sv", "slot_has_work"): "read only while hardwired",
    ("hardwired_control.sv", "writes_flags"): "read only while hardwired",
    ("microsequencer.sv", "return_stack"): "read only after a push",
    ("shifter.sv", "flags_cf"): "gated by sh_flags_commit",
    ("shifter.sv", "flags_of"): "gated by sh_flags_commit",
    ("shifter.sv", "flags_we_of"): "gated by sh_flags_commit",
    ("shifter.sv", "flags_we_zsp"): "gated by sh_flags_commit",
    ("z486.sv", "TMPeIP"): "written by the fault entry before use",
    ("z486.sv", "TMPeSP"): "written by the fault entry before use",
}


def balance(src, i):
    """Return the begin..end body whose `begin` is at offset i."""
    depth = 0
    j = i
    while j < len(src):
        if src.startswith("begin", j):
            depth += 1
            j += 5
            continue
        if src.startswith("end", j):
            depth -= 1
            j += 3
            if depth == 0:
                break
            continue
        j += 1
    return src[i:j]


def spans(src, pattern):
    """Yield (offset, body) for each keyword match with a balanced begin/end."""
    for m in re.finditer(pattern, src):
        i = src.find("begin", m.end())
        if i < 0:
            continue
        yield m.start(), balance(src, i)


def assigns(txt):
    return set(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*(?:\[[^\]]*\])?\s*<=", txt))


def main():
    findings = []
    for path in sorted(glob.glob(os.path.join(ROOT, "*.sv"))
                       + glob.glob(os.path.join(ROOT, "x87", "*.sv"))):
        src = open(path, errors="replace").read()
        for start, body in spans(src, r"always_ff\s*@"):
            m = re.search(r"if\s*\(\s*!?(?:reset_n|reset)\s*\)", body)
            if not m or body.find("begin", m.end()) < 0:
                continue
            reset_branch = balance(body, body.find("begin", m.end()))
            rest = body[m.start() + len(reset_branch):]
            em = re.search(r"else\s*begin", rest)
            if not em:
                continue
            else_branch = balance(rest, em.start() + em.group(0).rindex("begin"))
            missing = sorted(x for x in assigns(else_branch) - assigns(reset_branch)
                             if not x.startswith("_"))
            line = src[:start].count("\n") + 1
            for sig in missing:
                findings.append((os.path.relpath(path, ROOT), line, sig))

    new = [f for f in findings if (f[0], f[2]) not in ALLOW]
    if "--list" in sys.argv:
        for path, line, sig in findings:
            tag = "allow" if (path, sig) in ALLOW else "NEW"
            print(f"{tag:5} {path}:{line}: {sig}")
        return 0
    for path, line, sig in new:
        print(f"RESET GAP: {path}:{line}: {sig} is assigned but never reset")
    if new:
        print(f"\n{len(new)} new reset gap(s). Either reset them or add an ALLOW "
              f"entry in {os.path.relpath(__file__, ROOT)} with the reason.")
        return 1
    print(f"reset-list check: {len(findings)} known item(s), no new gaps")
    return 0


if __name__ == "__main__":
    sys.exit(main())
