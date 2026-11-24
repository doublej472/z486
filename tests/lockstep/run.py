#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Run the z486-vs-86Box lockstep over a program set and judge it against the known list.

usage: run.py --set quick|full --bin Vtb_lock [--jobs N] [--only SUBSTR ...]
              [--rand r:1-10,p:1-10,g:1-10] [--timeout S] [--known FILE] [--out DIR]

Every program runs twice: stepwise (-s, full state compared after every instruction;
the undefined-flag values it settles are recorded in a .sync file) and pipelined (-p,
the core runs freely, random bus timing, replaying that .sync file).

A run diverges when the harness prints LOCK MISMATCH (a state, store, flow, hang,
shutdown or INTA difference), prints no verdict, or times out.  Each divergence must be
listed in known-divergences.txt; one that is not fails the run (exit 1).  A listed
divergence that no longer appears is reported as GONE (a warning: a fix removed it, so
the entry should go).  Entries with counter=NAME are judged on the harness's tolerated-
difference counter NAME being nonzero instead (for findings the harness counts rather
than reports, such as the coprocessor I/O cycles of B2).
"""
import argparse
import concurrent.futures as cf
import os
import re
import resource
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent           # the z486 checkout: ROM images for the run directory
PROGS = HERE / 'progs'

QUICK_RAND = 'r:1-10,p:1-10,g:1-10,g:25,g:118,g:164,g:301'   # (+ the random B6 / B15 reproducers)
# the original evaluation's random sets: real mode 1-260, 16-bit PM 1-300, PM + paging 1-450
FULL_RAND = 'r:1-260,p:1-300,g:1-450'
RAND_FLAG = {'r': [], 'p': ['--pm'], 'g': ['--pg']}
HAZ = [(k, n) for k in ('adc', 'flagsrd', 'shld') for n in (1, 2, 3, 4)]


def sh(cmd, **kw):
    r = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, **kw)
    if r.returncode:
        sys.exit('lockstep: %s failed:\n%s' % (' '.join(map(str, cmd)), r.stdout))
    return r.stdout


def stale(out, *srcs):
    return not out.exists() or any(s.stat().st_mtime > out.stat().st_mtime for s in srcs)


def parse_rand(spec):
    out = []
    for part in spec.split(','):
        if not part:
            continue
        kind, rng = part.split(':')
        lo, _, hi = rng.partition('-')
        out += [(kind, s) for s in range(int(lo), int(hi or lo) + 1)]
    return out


def build_programs(args, work):
    """Assemble / generate the set; returns [(name, path)]."""
    progs = []
    for sub in ('dir', 'pmd'):
        d = work / 'progs' / sub
        d.mkdir(parents=True, exist_ok=True)
        incs = sorted((PROGS / sub).glob('*.inc'))
        for src in sorted((PROGS / sub).glob('*.asm')):
            out = d / (src.stem + '.com')
            if stale(out, src, *incs):
                sh(['nasm', '-f', 'bin', '-w-all', '-i', str(PROGS / sub) + '/', '-o', str(out), str(src)])
            progs.append(('%s/%s' % (sub, src.stem), out))
    if args.set == 'full':
        d = work / 'progs' / 'haz'
        d.mkdir(parents=True, exist_ok=True)
        gen = PROGS / 'haz' / 'gen_haz.py'
        for kind, n in HAZ:
            asm, out = d / ('%s_%d.asm' % (kind, n)), d / ('%s_%d.com' % (kind, n))
            if stale(out, gen):
                asm.write_text(sh([sys.executable, str(gen), kind, str(n), '150']))
                sh(['nasm', '-f', 'bin', '-w-all', '-o', str(out), str(asm)])
            progs.append(('haz/%s_%d' % (kind, n), out))
        tpm = Path(os.environ.get('LOCKSTEP_CACHE', HERE / 'build')) / 'tetrium' / 'tests' / 'pm'
        d = work / 'progs' / 'pm'
        d.mkdir(parents=True, exist_ok=True)
        srcs = sorted(tpm.glob('pm*.s'), key=lambda p: int(p.stem[2:]))
        if not srcs:
            sys.exit('lockstep: no Tetrium pm*.s under %s (run fetch.sh)' % tpm)
        for src in srcs:
            obj, out = d / (src.stem + '.o'), d / (src.stem + '.com')
            if stale(out, src):
                sh(['as', '--32', '-o', str(obj), str(src)])
                sh(['objcopy', '-O', 'binary', str(obj), str(out)])
            progs.append(('pm/%s' % src.stem, out))
    gen = PROGS / 'rgen386.py'
    d = work / 'progs' / 'rand'
    d.mkdir(parents=True, exist_ok=True)
    for kind, seed in parse_rand(args.rand or (QUICK_RAND if args.set == 'quick' else FULL_RAND)):
        out = d / ('%s%d.bin' % (kind, seed))
        if stale(out, gen):
            sh([sys.executable, str(gen), str(out), str(seed), '3000'] + RAND_FLAG[kind])
        progs.append(('rand/%s%d' % (kind, seed), out))
    if args.only:
        progs = [p for p in progs if any(o in p[0] for o in args.only)]
    return progs


def run_dir(work):
    """The harness reads its ROM images from the current directory."""
    rd = work / 'run'
    rd.mkdir(parents=True, exist_ok=True)
    for src in list(ROOT.glob('*.hex')) + [ROOT / 'x87' / 'x87_ucode.mem']:
        link = rd / src.name
        if link.is_symlink() or link.exists():
            link.unlink()
        link.symlink_to(src)
    return rd


LOCK_RE = re.compile(r'LOCK (OK|MISMATCH) (step|pipe)(.*)')


def one_run(binary, rd, prog, mode, sync, timeout):
    cmd = [str(binary), '-s' if mode == 'step' else '-p', '-sync', str(sync), str(prog)]
    t0 = time.time()
    try:
        r = subprocess.run(cmd, cwd=rd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        text = r.stdout.decode('latin-1')
    except subprocess.TimeoutExpired:
        return {'div': True, 'kind': 'timeout', 'text': 'no verdict after %ds' % timeout, 'cnt': {}, 'sec': timeout}
    sec = time.time() - t0
    m = None
    for line in text.splitlines():
        m = LOCK_RE.search(line)
        if m:
            break
    if not m:
        tail = ' | '.join(text.strip().splitlines()[-3:])
        return {'div': True, 'kind': 'noverdict', 'text': tail[:300], 'cnt': {}, 'sec': sec}
    rest = m.group(3)
    cnt = {k: int(v) for k, v in re.findall(r'(\w+)=(\d+)', rest)} if m.group(1) == 'OK' else {}
    if m.group(1) == 'OK':
        return {'div': False, 'kind': 'ok', 'text': '', 'cnt': cnt, 'sec': sec}
    km = re.search(r'first: (\w+)', rest)
    kind = km.group(1) if km else 'mem'
    return {'div': True, 'kind': kind, 'text': rest.strip()[:400], 'cnt': cnt, 'sec': sec}


def run_prog(binary, rd, work, name, prog, timeout):
    sync = work / 'sync' / (name.replace('/', '_') + '.sync')
    sync.parent.mkdir(parents=True, exist_ok=True)
    return name, {m: one_run(binary, rd, prog, m, sync, timeout) for m in ('step', 'pipe')}


def load_known(path):
    known = []
    for n, line in enumerate(path.read_text().splitlines(), 1):
        line = line.split('#', 1)[0].strip()
        if not line:
            continue
        f = line.split()
        if len(f) < 3:
            sys.exit('%s:%d: want "FINDING PROGRAM MODES [counter=NAME]"' % (path, n))
        modes = f[2].split(',')
        if not set(modes) <= {'step', 'pipe'}:
            sys.exit('%s:%d: modes are step, pipe or step,pipe' % (path, n))
        counter = None
        for opt in f[3:]:
            if opt.startswith('counter='):
                counter = opt[8:]
            else:
                sys.exit('%s:%d: unknown option %s' % (path, n, opt))
        known.append({'id': f[0], 'prog': f[1], 'modes': modes, 'counter': counter, 'line': n})
    return known


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--set', choices=('quick', 'full'), default='quick')
    ap.add_argument('--bin', required=True)
    ap.add_argument('--jobs', type=int, default=4)
    ap.add_argument('--only', action='append', help='run only programs whose name contains this')
    ap.add_argument('--rand', help='random programs, e.g. r:1-10,p:1-10,g:1-10 (r real, p PM, g PM+paging)')
    ap.add_argument('--timeout', type=int, default=300, help='wall-clock limit per run, seconds')
    ap.add_argument('--known', default=str(HERE / 'known-divergences.txt'))
    ap.add_argument('--out', help='work directory (default $LOCKSTEP_CACHE/run-<set>)')
    args = ap.parse_args()

    binary = Path(args.bin).resolve()
    if not binary.exists():
        sys.exit('lockstep: %s missing (make -C tests lockstep-build)' % binary)
    cache = Path(os.environ.get('LOCKSTEP_CACHE', HERE / 'build'))
    work = Path(args.out) if args.out else cache / ('run-' + args.set)
    work.mkdir(parents=True, exist_ok=True)
    known = load_known(Path(args.known))
    progs = build_programs(args, work)
    rd = run_dir(work)

    t0 = time.time()
    res = {}
    print('lockstep: %d programs x 2 modes, %d jobs' % (len(progs), args.jobs), flush=True)
    with cf.ThreadPoolExecutor(max_workers=args.jobs) as ex:
        futs = [ex.submit(run_prog, binary, rd, work, n, p, args.timeout) for n, p in progs]
        for i, fu in enumerate(cf.as_completed(futs), 1):
            name, r = fu.result()
            res[name] = r
            if i % 25 == 0 or i == len(futs):
                print('  %d/%d done (%.0fs)' % (i, len(futs), time.time() - t0), flush=True)
    wall = time.time() - t0
    peak = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss / 1024

    unexpected, gone, rows = [], [], []
    for name, _ in progs:
        r = res[name]
        ents = [k for k in known if k['prog'] == name]
        row = {'prog': name}
        verdicts = []
        for mode in ('step', 'pipe'):
            x = r[mode]
            mine = [k for k in ents if mode in k['modes']]
            shows = []
            for k in mine:
                hit = x['cnt'].get(k['counter'], 0) > 0 if k['counter'] else x['div']
                if hit:
                    shows.append(k['id'])
                else:
                    gone.append('%s %s %s (%s:%d)' % (k['id'], name, mode, Path(args.known).name, k['line']))
            covered = any(not k['counter'] for k in mine)
            cell = x['kind'] if x['div'] else 'ok'
            for k in mine:
                if k['counter'] and x['cnt'].get(k['counter'], 0) > 0:
                    cell += ' %s=%d' % (k['counter'], x['cnt'][k['counter']])
            row[mode] = cell
            if x['div'] and not covered:
                unexpected.append('%s %s: %s' % (name, mode, x['text'] or x['kind']))
                verdicts.append('UNEXPECTED')
            elif any(k['id'] in shows for k in mine):
                verdicts.append('known')
            elif mine:
                verdicts.append('GONE')
            row.setdefault('ids', set()).update(k['id'] for k in mine)
        row['verdict'] = 'UNEXPECTED' if 'UNEXPECTED' in verdicts else 'GONE' if 'GONE' in verdicts else \
            'known' if verdicts else 'pass'
        row['text'] = r['step']['text'] or r['pipe']['text']
        rows.append(row)

    lines = ['%-28s %-22s %-22s %-14s %s' % ('program', 'step', 'pipe', 'listed', 'verdict')]
    for row in rows:
        lines.append('%-28s %-22s %-22s %-14s %s' % (row['prog'], row['step'], row['pipe'],
                                                    ','.join(sorted(row['ids'])) or '-', row['verdict']))
    detail = ['', 'first difference per diverging program:']
    for row in rows:
        if row['text']:
            detail.append('  %s: %s' % (row['prog'], row['text']))
    summary = ['', 'lockstep %s: %d programs, %d pass, %d known, %d UNEXPECTED, %d GONE; %.0fs wall, peak RSS %.0f MB'
               % (args.set, len(rows), sum(r['verdict'] == 'pass' for r in rows),
                  sum(r['verdict'] == 'known' for r in rows), sum(r['verdict'] == 'UNEXPECTED' for r in rows),
                  sum(r['verdict'] == 'GONE' for r in rows), wall, peak)]
    for g in gone:
        summary.append('WARNING: known divergence no longer appears: %s' % g)
    for u in unexpected:
        summary.append('UNEXPECTED: %s' % u)
    report = '\n'.join(lines + detail + summary) + '\n'
    (work / 'results.txt').write_text(report)
    print('\n'.join(lines))
    print('\n'.join(summary))
    print('lockstep: table and first differences in %s' % (work / 'results.txt'))
    return 1 if unexpected else 0


if __name__ == '__main__':
    sys.exit(main())
