#!/usr/bin/env python3
"""Combinational equivalence proofs for zero-cycle rewrites (yosys SAT).

Each tests/equiv/<name>.v holds a module <name> with one output `mismatch`
that compares a rewritten expression against the form it replaced, and a
`parameter MUTANT = 0`.  The proof is `sat -prove mismatch 0` over EVERY
input bit.  Each proof is run twice:

  MUTANT=0  must PROVE (the rewrite is bit-identical for all inputs);
  MUTANT=1  must FAIL with a counterexample (a planted error the proof has to
            see - so a proof that is vacuous, or a model that no longer
            reaches `mismatch`, cannot pass silently).

The models restate the RTL expressions they prove; each file names its RTL
site.  A model whose first line is `// check-equiv: tempinduct` is sequential
and is proved by temporal induction from its declared power-up values.  yosys
is required: a missing yosys is a FAIL, never a skip.
"""
import pathlib
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
EQUIV = HERE / "equiv"


def run(path: pathlib.Path, mutant: int) -> bool:
    top = path.stem
    # A model whose first line is "// check-equiv: tempinduct" is sequential: it
    # is proved by temporal induction from its declared power-up values.
    seq = path.read_text().startswith("// check-equiv: tempinduct")
    sat = ("sat -tempinduct -prove mismatch 0 -verify" if seq
           else "sat -prove mismatch 0 -verify -show-inputs")
    script = (f"read_verilog -sv {path}; chparam -set MUTANT {mutant} {top}; "
              f"prep -top {top}; flatten; {sat}")
    r = subprocess.run(["yosys", "-q", "-p", script],
                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    return r.returncode == 0


def main() -> int:
    if shutil.which("yosys") is None:
        print("check-equiv: FAIL - yosys not found (required, not optional)")
        return 1
    proofs = sorted(EQUIV.glob("*.v"))
    if not proofs:
        print("check-equiv: no proofs in tests/equiv/")
        return 0
    bad = 0
    for p in proofs:
        ok = run(p, 0)
        mut_caught = not run(p, 1)
        verdict = "PASS" if (ok and mut_caught) else "FAIL"
        if verdict == "FAIL":
            bad += 1
        print(f"  {p.stem:32s} proof={'proved' if ok else 'REFUTED'} "
              f"mutant={'caught' if mut_caught else 'MISSED'}  {verdict}")
    print(f"check-equiv: {len(proofs) - bad}/{len(proofs)} PASS")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
