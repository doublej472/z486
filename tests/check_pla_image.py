#!/usr/bin/env python3
"""Regenerate the PLA in scratch and compare the COMMITTED image, not itself."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def words(path):
    return [int(w, 16) for line in path.read_text().splitlines()
            for w in line.split('//', 1)[0].split()]


def main():
    with tempfile.TemporaryDirectory(prefix='z486-pla-') as d:
        work = Path(d)
        command = [os.environ.get('VERILATOR', 'verilator'), '--binary',
                   '-Wno-fatal', '-j', os.environ.get('JOBS', '8'),
                   '-I' + str(ROOT), '--Mdir', str(work / 'obj'),
                   '--top-module', 'gen_pla_entry_rom',
                   str(ROOT / 'scripts/gen_pla_entry_rom.sv')]
        built = subprocess.run(command, capture_output=True, text=True, timeout=120)
        if built.returncode:
            print(built.stdout + built.stderr)
            return 1
        ran = subprocess.run([str(work / 'obj/Vgen_pla_entry_rom')], cwd=work,
                             capture_output=True, text=True, timeout=30)
        if ran.returncode:
            print(ran.stdout + ran.stderr)
            return 1
        generated = words(work / 'pla_entry_rom.hex')
        committed = words(ROOT / 'pla_entry_rom.hex')
        if len(generated) != 1024 or committed != generated:
            print('PLA IMAGE FAIL: committed pla_entry_rom.hex differs from pla_entry_lookup')
            return 1
        print('PLA IMAGE PASS: 1024 committed words, all 4096 mode lanes verified')
        return 0


if __name__ == '__main__':
    raise SystemExit(main())
