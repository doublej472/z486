# Lockstep test against 86Box

This directory runs the z486 RTL (Verilator) instruction by instruction next to the 86Box
i486SX interpreter, as packaged by Tetrium's `tb/x86ref` (`libx86ref.a`), and reports
every architectural difference: registers, EIP, EFLAGS, selectors and descriptor caches,
CPL, LDTR/TR, CR0/2/3, DR6/7, every stored byte, every OUT byte, the instruction flow and
INTA cycles.

## Licence

Everything under `tests/lockstep/` is GPL-3.0-or-later ([LICENSE](LICENSE)), unlike the
rest of the repository. The harness links the GPL-3 reference model and follows Tetrium's
testbench (`tb/tb_main.cpp`) and its program generator (`progs/rgen386.py`), so it carries
their licence. It is test-only: no file here is part of the synthesized CPU, and no RTL
file includes or depends on it. Tetrium and 86Box are not vendored: `fetch.sh` clones them
at pinned commits into the ignored build directory.

## Requirements

Verilator 5 (the one the other tests use), `nasm`, GNU `as` and `objcopy` (for Tetrium's
`pm*.s` in the full set), a C/C++ compiler, Python 3 and git. The first build needs
network access (or local clones, below).

## Fetch, build, run

```
make -C tests lockstep-quick LOCKSTEP_JOBS=4   # reproducers + a seeded random batch
make -C tests lockstep LOCKSTEP_JOBS=4         # the full set
```

The first invocation runs `fetch.sh`: it clones Tetrium at `d5caa5a` and 86Box at
`7b2dbc0` (the commit Tetrium's `tests/fetch.sh` pins), lets Tetrium's
`tb/x86ref/build.sh` apply its 486 patch and builds `libx86ref.a` (about 30 s at 4 jobs).
The lockstep binary (`Vtb_lock`, about 30 s) is built from the same RTL list as the other
benches (`RTL_SRCS` in `tests/Makefile`) and rebuilt when the RTL changes.

| variable | default | meaning |
|---|---|---|
| `LOCKSTEP_CACHE` | `tests/lockstep/build` | clones, `libx86ref.a`, `Vtb_lock`, assembled programs, results |
| `LOCKSTEP_TETRIUM_URL` | the public Tetrium repository | clone source (a local checkout that holds `d5caa5a` works offline) |
| `LOCKSTEP_86BOX_URL` | the public 86Box repository | clone source for 86Box |
| `LOCKSTEP_JOBS` | 4 | compile jobs and parallel lockstep runs |
| `LOCKSTEP_ARGS` | | extra `run.py` options, e.g. `--only esc` or `--rand g:1-40` |

These targets are not part of `test-release`: they need a network fetch the first time.
`rm -rf tests/lockstep/build` (or the cache directory) starts over.

### Program sets

| set | programs | where they come from |
|---|---|---|
| `dir/*` | directed real-mode reproducers (ESC forms, instruction length, INTR withdrawal, flags after REP strings, stack wrap, transfers beyond the CS limit) | `progs/dir/*.asm` |
| `pmd/*` | directed protected-mode reproducers (outer RETF/IRET faults, RMW #PF, descriptor-table and IDT limits, error-code width, data breakpoints, ARPL, execute-only CS reads) | `progs/pmd/*.asm`, prologues `pmhead*.inc` |
| `haz/*` (full) | pipeline-hazard programs (ADC/SBB, flag readers, SHLD/SHRD), 12 x 150 cases | `progs/haz/gen_haz.py KIND N 150` |
| `pm/*` (full) | Tetrium's directed PM / paging / V86 / task / debug tests pm1-pm24 | the fetched Tetrium `tests/pm/*.s` |
| `rand/rN`, `pN`, `gN` | 3000-instruction random programs: real mode, 16-bit PM, PM with paging and a demand-paging #PF handler | `progs/rgen386.py OUT SEED 3000 [--pm|--pg]` |

The quick set is `dir`, `pmd`, random seeds 1-10 of each kind and the four random
seeds that first showed B6 and B15 (g25, g118, g164, g301); the full set adds
`haz`, `pm` and the random seeds of the original evaluation (r 1-260, p 1-300, g 1-450).
The generated programs are rebuilt from their seeds; none is committed.

### Run time and memory

One lockstep process holds about 220 MB (two 16 MB memory images, the model, the
Verilator model); 4 jobs need under 1 GB. At 4 jobs the
quick set (181 programs, two runs each) takes about a minute; the full set (1,193
programs) about 12 minutes, 4 of them generating the random programs on the first run.
Run it at low priority with a memory cap, e.g.

```
nice -n 19 systemd-run --user --scope -p MemoryMax=12G -p MemorySwapMax=0 \
    make -C tests lockstep-quick LOCKSTEP_JOBS=4
```

## Modes

Every program runs twice:

- **stepwise** (`-s`): issue is serialised through the core's instruction-breakpoint hold;
  at every settled boundary the full state is compared, the instruction's undefined flags
  are masked, copied into the model and written to a `.sync` file. An external
  interrupt the core acknowledged is handed to the model before that compare (the core
  enters the handler before it settles): in both modes the model takes each interrupt at
  the boundary where the core acknowledged it, so the harness checks that INTR was still
  asserted at the acknowledge (`intr` below), not which boundary recognised it;
- **pipelined** (`-p`): the core runs freely on a randomised bus (0-6 wait reads, whole-line
  or beat fills, write holds); every issued EIP is checked against the model, and at the
  stop the full state and the whole memory image are compared. The `.sync` file replays
  the undefined-flag values.

`build/obj/Vtb_lock -h` lists the options (`-n N` stop after N instructions, `-lat 0|1|2`
bus timing, `-kr` resynchronise and count, `-v` trace every instruction); a plusarg
`+trace` traces the core every cycle, `+dbmode` forces the core's DR7 mode.

## Reading the result

`run.py` prints one row per program and writes it, with each diverging program's first
difference, to `$LOCKSTEP_CACHE/run-<set>/results.txt`:

```
program                      step                   pipe                   listed         verdict
dir/esc2                     ok cpio=20             ok cpio=20             B2             known
dir/len18                    hang                   hang                   B3             known
pmd/b6min                    ok                     ok                     -              pass
```

- `ok`: no difference. Otherwise the kind of the first difference: `state` (registers or
  stores after an instruction), `final` (the pipelined end state), `flow` (the core issued
  another EIP than the model executes next), `hang` (no issue for 200k cycles), `intr`
  (an INTA for an INTR that was withdrawn before the boundary), `shutdown`, `out`
  (OUT bytes left over), `mem` (the final memory images differ), `timeout`, `noverdict`.
- A difference reads `DUT/model`: `eax=00000000/11112222` is z486 EAX 0, 86Box 11112222;
  `st[008062]=4d/4e` a stored byte; `(nw)` marks the side that did not write it.
  `state insn 28 at 0008:00000158 [9a 00 ...]` is the model's instruction count, CS:EIP
  and instruction bytes.
- Counters on an `ok` line are tolerated differences (the harness syncs them): `rfmask`
  (RF in a fault frame), `selpad` / `errpad` (upper word of a pushed selector or error
  code), `cr0res`, `cr2` / `cr2blk` (CR2 of a multi-byte access / a fetch #PF), `cpio`
  (386 coprocessor I/O cycles, B2), `fetchf` / `squash` / `defer` (harness alignment).
- To dig in: `cd $LOCKSTEP_CACHE/run-quick/run && ../../obj/Vtb_lock -s -v ../progs/dir/esc2.com`
  (`LOCKST=1` prints the store logs, `LOCKPRE=1` the state before a mismatching
  instruction, `LOCKIO=1` the OUT cycles).

### Known divergences

`known-divergences.txt` lists every divergence still expected, one line per program:
the finding, the program, the modes it shows in, and optionally `counter=NAME` for a
finding the harness counts instead of reporting. Exit status: nonzero when a run diverges
and no line lists it (`UNEXPECTED`). A listed divergence that no longer appears is
reported as `GONE` with a warning; the exit status stays zero, but the line should be
removed together with the fix. Findings `B*` are z486 bugs; `D*` are documented
implementation differences and `H*` harness limits, which a bug fix is not expected to
remove.
