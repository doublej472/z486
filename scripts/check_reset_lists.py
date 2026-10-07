#!/usr/bin/env python3
"""Audit explicit reset branches in always_ff blocks (not reset-less pipelines).

Tokenize comments/strings and parse procedural statement boundaries, including
case/endcase, loops and unbraced if/else. Compare nonblocking assignment targets
against the reset branch; a whole-struct reset covers its members. This is a
structural omission check, not proof of reset reachability or X-free operation.

Usage: scripts/check_reset_lists.py [--list] [--root PATH]
"""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parent.parent

# Valid-gated payloads intentionally not reset. Control bits must be reset.
ALLOW = {
    **{("data_unit.sv", "flag2_" + f + "_r"): "paired flag2_*_p reset gates payload"
       for f in ("af", "cf", "of", "result", "size", "zsp")},
    **{("hardwired_control.sv", "recipe_state." + f): "recipe_state.hardwired resets to 0"
       for f in ("commit_sel", "jcc", "multi_ustep", "slot_has_work", "writes_flags")},
    ("microsequencer.sv", "return_stack"): "read only after a push",
    **{("shifter.sv", f): "gated by reset sh_flags_commit"
       for f in ("flags_cf", "flags_of", "flags_value_r", "flags_we_of", "flags_we_zsp")},
    ("data_unit.sv", "recipe_shift_data"): "recipe_shift_write.valid resets to 0",
    ("decoder.sv", "skel"): "skel_v resets to 0",
    ("decoder.sv", "skel_lit_off"): "skel_v resets to 0",
    ("decoder.sv", "workB"): "d2_phaseB resets to 0; capA writes before phase B",
    **{("l1_cache.sv", f): "patch_fwd_valid_r resets to 0"
       for f in ("patch_fwd_addr_r", "patch_fwd_data_r", "patch_fwd_way_r")},
    **{(cache, f): "assigned at miss before S_FILL; FSM resets to S_RESET_INIT"
       for cache in ("l1_cache.sv", "l1_icache.sv")
       for f in ("fill_count", "fill_plru_r", "fill_set", "fill_tag", "fill_way")},
    ("l1_cache.sv", "fill_target_word"): "assigned at miss before S_FILL",
    **{(cache, "plru_set"): "reset-init sweep initializes every set before ready"
       for cache in ("l1_cache.sv", "l1_icache.sv")},
    **{(cache, f): "request captured before S_LOOKUP; req_valid_r resets to 0"
       for cache in ("l1_cache.sv", "l1_icache.sv")
       for f in ("req_addr_r", "req_set_r", "req_tag_r", "req_uncacheable_r")},
    **{("l1_cache.sv", f): "request captured before S_LOOKUP; req_valid_r resets to 0"
       for f in ("req_be_r", "req_din_r", "req_protect_write_r", "req_word_r", "req_write_r")},
    **{("l1_icache.sv", f): "request captured before S_LOOKUP"
       for f in ("req_no_alloc_r", "req_no_fill_r")},
    **{("l1_cache.sv", f): "request captured before S_LOOKUP; req_valid_r resets to 0"
       for f in ("req_nw_r",)},
    ("l1_cache.sv", "nw_hit_r"): "written in S_LOOKUP on entry to S_NW_WRITE, its only reader",
    **{("l1_cache.sv", f): "storeq_valid and count reset; enqueue writes payload"
       for f in ("storeq_addr", "storeq_be", "storeq_data")},
    **{("l1_icache.sv", f): "patchq_valid resets to 0; patch capture writes payload"
       for f in ("patchq_addr", "patchq_be", "patchq_data")},
    **{("mul_div.sv", f): "microcode setup writes scratch before MUL/DIV iterations"
       for f in ("divtmp", "multmp", "result_r")},
    **{("paging_tlb.sv", f): "valid_q resets to 0; TLB insertion writes attributes"
       for f in ("dirty_q", "pcd_q", "pwt_q", "user_q", "vga_mem", "writable_q")},
    ("prefetch.sv", "prefetch_queue"): "queue_count resets to 0; fill writes bytes",
    ("prefetch.sv", "spec_line"): "spec_valid resets to 0; speculative fill writes line",
    ("prefetch.sv", "spec_b_line"): "spec_b_valid resets to 0; speculative fill writes line",
    ("z486.sv", "rsb"): "rsb_valid resets to 0; CALL writes before prediction",
    ("z486.sv", "ret_pred_r"): "captured at RET issue; only speculative prediction comparison consumes it",
    ("x87/x87_control.sv", "tag_word"): "separate tag write process applies reset's full-tag command",
}

# Retain offsets for diagnostics; comments, strings and attributes are not code.
TOKEN = re.compile(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|'
                   r'\(\*[\s\S]*?\*\)|[A-Za-z_$][\w$]*|<=|[^\s]')
IDENT = re.compile(r'^[A-Za-z_$][\w$]*$')


def tokens(src):
    return [(m.group(), m.start()) for m in TOKEN.finditer(src)
            if not m.group().startswith(('//', '/*', '"', '(*'))]


class Statements:
    """Small procedural parser; nodes carry (kind, start, end, children)."""
    def __init__(self, ts):
        self.ts = ts
        self.t = [x[0] for x in ts]

    def group(self, i):
        closing = {'(': ')', '[': ']', '{': '}'}
        stack = [closing[self.t[i]]]
        i += 1
        while i < len(self.t) and stack:
            if self.t[i] in closing:
                stack.append(closing[self.t[i]])
            elif self.t[i] == stack[-1]:
                stack.pop()
            i += 1
        if stack:
            raise ValueError('unterminated delimiter')
        return i

    def statement(self, i):
        start = i
        kind = self.t[i]
        kids = []
        if kind in ('unique', 'unique0', 'priority'):
            return self.statement(i + 1)
        if kind == 'fork':
            raise ValueError('fork in always_ff is not supported')
        if kind == 'begin':
            i += 1
            if self.t[i] == ':':  # named block
                i += 2
            while self.t[i] != 'end':
                child, i = self.statement(i)
                kids.append(child)
            i += 1
            if i < len(self.t) and self.t[i] == ':':
                i += 2
        elif kind == 'if':
            cond_start = i + 1
            i = self.group(cond_start)
            child, i = self.statement(i)
            kids.append(child)
            if i < len(self.t) and self.t[i] == 'else':
                child, i = self.statement(i + 1)
                kids.append(child)
        elif kind in ('case', 'casex', 'casez'):
            i = self.group(i + 1)
            while self.t[i] != 'endcase':
                # Case item labels are expressions, not assignment statements.
                while self.t[i] != ':':
                    i = self.group(i) if self.t[i] in ('(', '[', '{') else i + 1
                child, i = self.statement(i + 1)
                kids.append(child)
            i += 1
        elif kind in ('for', 'foreach', 'while', 'repeat'):
            i = self.group(i + 1)
            child, i = self.statement(i)
            kids.append(child)
        elif kind == 'forever':
            child, i = self.statement(i + 1)
            kids.append(child)
        elif kind == 'do':
            child, i = self.statement(i + 1)
            kids.append(child)
            if self.t[i] != 'while':
                raise ValueError('do without while')
            i = self.group(i + 1) + 1
        else:
            # Simple statement. Skip nested RHS delimiters to its semicolon.
            while self.t[i] != ';':
                i = self.group(i) if self.t[i] in ('(', '[', '{') else i + 1
            i += 1
        return (kind, start, i, kids), i

    def lhs(self, i):
        """Targets of a scalar/member/array/concatenated nonblocking LHS."""
        if self.t[i] == '{':
            stop = self.group(i)
            names = set()
            i += 1
            while i < stop - 1:
                part, i = self.lhs(i)
                names |= part
                if self.t[i] == ',':
                    i += 1
            return names, stop
        if not IDENT.match(self.t[i]):
            return set(), i + 1
        name = self.t[i]
        i += 1
        while i < len(self.t):
            if self.t[i] == '[':
                i = self.group(i)
            elif self.t[i] == '.':
                name += '.' + self.t[i + 1]
                i += 2
            else:
                break
        return {name}, i

    def assigns(self, node):
        kind, start, _, kids = node
        if kids:
            return set().union(*(self.assigns(k) for k in kids))
        names, i = self.lhs(start)
        return names if self.t[i] == '<=' else set()

    def reset_nodes(self, node):
        kind, start, _, kids = node
        if kind == 'if':
            stop = self.group(start + 1)
            cond = self.t[start + 2:stop - 1]
            if cond in (['!', 'reset_n'], ['reset']):
                yield node, kids[0]
                return
            if cond in (['reset_n'], ['!', 'reset']) and len(kids) == 2:
                yield node, kids[1]  # inverse condition: reset is the else arm
                return
        for k in kids:
            yield from self.reset_nodes(k)


def findings(src):
    ts = tokens(src)
    p = Statements(ts)
    for i, (t, off) in enumerate(ts):
        if t != 'always_ff':
            continue
        j = i + 1
        if p.t[j] != '@':
            raise ValueError('always_ff without event control')
        j += 1
        j = p.group(j) if p.t[j] == '(' else j + 1
        body, _ = p.statement(j)
        for reset, reset_branch in p.reset_nodes(body):
            reset_assigned = p.assigns(reset_branch)
            normal = p.assigns(body) - reset_assigned
            for sig in sorted(normal):
                if not any(sig == r or sig.startswith(r + '.') for r in reset_assigned):
                    yield src[:off].count('\n') + 1, sig


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--list', action='store_true')
    ap.add_argument('--root', type=Path, default=ROOT)
    args = ap.parse_args()
    root = args.root.resolve()
    found = []
    for path in sorted(list(root.glob('*.sv')) + list((root / 'x87').glob('*.sv'))):
        try:
            found.extend((str(path.relative_to(root)), line, sig)
                         for line, sig in findings(path.read_text()))
        except (ValueError, IndexError) as e:
            print(f'RESET AUDIT PARSE ERROR: {path}: {e}')
            return 1  # Never turn an unsupported construct into a green gate.
    new = [f for f in found if (f[0], f[2]) not in ALLOW]
    for path, line, sig in found if args.list else new:
        reason = ALLOW.get((path, sig))
        print(f'{"allow" if reason else "RESET GAP"} {path}:{line}: {sig}'
              + (f' ({reason})' if reason else ' is assigned but never reset'))
    if new:
        print(f'{len(new)} new reset gap(s); reset or justify each payload in ALLOW.')
        return 1
    print(f'reset-list check: {len(found)} known item(s), no new gaps')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
