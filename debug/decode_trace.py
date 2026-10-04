#!/usr/bin/env python3
"""Decode an instruction trace captured from the core's debug UART.

    tools/decode_trace.py CAPTURE [--pack build/pc98pack.bin] [--bank 4]

The trace is the last N EIP transitions the CPU made before it stopped, recorded by
pc9821_trace.sv and streamed after the stall. It is preceded by one CONTEXT line:

    CTX A=AAAAAAAA W=v V=v R=v S=v F=v

the state of the memory port at the instant the detector fired, and then a record per transition:

    CCCC:EEEEEEEE,DDDD          CS, EIP, and the cycles spent there

HOW TO READ IT. THE CONTEXT LINE IS THE ANSWER; the records are the path that led to it. V=1 with
R=0 means a request was PRESENTED AND REFUSED, so the wait is downstream of the CPU and whatever
answers that address never accepted it; V=0 means nothing is on the bus at all, so the fault is
above the port or the CPU is somewhere its own logic cannot leave. THE ADDRESS CARRIES THE SPLIT BY
ITSELF: an I/O port is below 0x10000, GVRAM is at 0xA8000, the intensity plane at 0xE0000, and the
pack above 0x02000000. F=1 means the FONT port is also in flight - a second requester into the same
SDRAM controller, so it can hold the backend while this one waits.
In the records, the last line is the PC the guest stopped on and its dwell is 0xFFFF because it
never left - that is what the module writes when the stall detector fires. A dwell of one or two
cycles is an instruction that ran normally; a very large dwell is something that took a long time
without changing PC.

WHAT THIS CANNOT SAY. The trace carries no bank register, so an address in the 0xF8000 window
is resolved against --bank (4 by default, which is the reset ITF bank and what the guest runs
out of until it selects another). If the guest switched banks during the captured window, the
bytes printed for those addresses are from the wrong bank - the PC is still right, the code
shown is not. Nothing in the message says which bank was live at the time.
"""

import argparse
import pathlib
import re
import sys

LINE_RE = re.compile(r"^([0-9A-Fa-f]{4}):([0-9A-Fa-f]{8}),([0-9A-Fa-f]{4})\s*$")
# The stall context, printed once between the header and the first record. Every field is labelled
# in the capture itself, so this parses what a human reads rather than a packing nobody can see.
CTX_RE = re.compile(r"^CTX A=([0-9A-Fa-f]{8}) W=([01]) V=([01]) R=([01]) S=([01]) F=([01])\s*$")

# The 0xF8000 window is bank-selected by port 0x043F, so its pack offset is not a constant. The
# four ROM banks that can appear there live at these pack offsets (tools/pack_layout.py).
WINDOW_BASE = 0xF8000
WINDOW_SIZE = 0x8000
BANK_OFFSET = {0: 0x31000, 1: 0x39000, 2: 0x41000, 3: 0x70000, 4: 0x00000}

WEDGED_DWELL = 0xFFFF


def parse_trace(text):
    """The stall context and every trace line in the capture, in the order they were sent.

    The watchdog message interleaves with the trace (both go out on one UART), so lines that are
    not trace lines are skipped rather than being an error.
    """
    entries = []
    context = None
    inside = False
    for raw in text.splitlines():
        line = raw.strip()
        if line == "TRACE":
            inside = True
            continue
        if line == "TRACE END":
            inside = False
            continue
        if not inside:
            continue
        ctx = CTX_RE.match(line)
        if ctx:
            context = tuple(int(g, 16) for g in ctx.groups())
            continue
        match = LINE_RE.match(line)
        if match:
            entries.append((int(match.group(1), 16), int(match.group(2), 16),
                            int(match.group(3), 16)))
    return context, entries


def where_is(addr):
    """Which part of the machine a stuck address is in. The split the instrument exists for."""
    if addr < 0x10000:
        return "an I/O PORT - the access never left the device fabric"
    if 0xA8000 <= addr <= 0xBFFFF:
        # MATCH THE RTL'S DECODE EXACTLY: pc9821_memory_map takes bits [16:15] of the low 20 bits
        # and subtracts one, which is the window number. A plain `addr >> 15` also carries bit 20,
        # so 0xA8000 landed on plane 20 and printed "plane ?" - the same address the RTL calls
        # plane 0. Masking to the two bits the mapper actually reads is what makes the two agree.
        plane = {0: "B (blue)", 1: "R (red)", 2: "G (green)"}.get(((addr >> 15) & 3) - 1, "?")
        return f"GVRAM plane {plane} - the graphics write/read path"
    if 0xE0000 <= addr <= 0xE7FFF:
        return "GVRAM intensity plane"
    if addr >= 0x02000000:
        return "the firmware PACK - the ROM loader's own window"
    return "neither I/O nor GVRAM: a memory address in the mapped region"


def pack_offset(linear, bank):
    """Where a guest linear address lives in the pack, or None if it is not ROM."""
    if WINDOW_BASE <= linear < WINDOW_BASE + WINDOW_SIZE:
        base = BANK_OFFSET.get(bank)
        return None if base is None else base + (linear - WINDOW_BASE)
    # The E8000 lower shadow mirrors the same bank at the same offset, which is how the BIOS
    # reads a selected bank as data.
    if 0xE8000 <= linear < 0xF0000:
        base = BANK_OFFSET.get(bank)
        return None if base is None else base + (linear - 0xE8000)
    return None


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("capture", type=pathlib.Path)
    ap.add_argument("--pack", type=pathlib.Path, default=pathlib.Path("build/pc98pack.bin"),
                    help="the firmware pack (default: build/pc98pack.bin)")
    ap.add_argument("--bank", type=int, default=4, choices=sorted(BANK_OFFSET),
                    help="the bank live in the 0xF8000 window when the trace was taken "
                         "(default 4, the reset ITF bank)")
    ap.add_argument("--bytes", type=int, default=8,
                    help="instruction bytes to show per entry (default 8)")
    args = ap.parse_args()

    if not args.capture.is_file():
        print(f"no such capture: {args.capture}", file=sys.stderr)
        return 2

    context, entries = parse_trace(args.capture.read_text(errors="replace"))

    # THE CONTEXT COMES FIRST, because it answers the question the records only narrow down: the
    # ring says where the CPU HAD BEEN, and this says what it was WAITING FOR when it stopped.
    if context is not None:
        addr, wr, val, rdy, resp, fmem = context
        print("== what the CPU was waiting for, at the instant the detector fired")
        print(f"   address 0x{addr:08X} - {where_is(addr)}")
        print(f"   {'store' if wr else 'load'}, request valid={val} ready={rdy} response={resp},"
              f" font port in flight={fmem}")
        if val and not rdy:
            print("   V=1 R=0: THE REQUEST IS PRESENTED AND REFUSED. The wait is downstream of the")
            print("            CPU - whatever answers this address never accepted it.")
        elif not val:
            print("   V=0: no request is on the port at all. Nothing is hanging ON THE BUS, so the")
            print("        CPU is somewhere its own logic cannot leave, or the request never reached")
            print("        this port and the fault is above it in the mux.")
        if fmem:
            print("   F=1: THE FONT PORT IS ALSO IN FLIGHT. It is a second requester into the same")
            print("        SDRAM controller, so it can hold the backend while this one waits.")
        print()
    else:
        print("note: no CTX line in this capture - the dump predates the context field, or the")
        print("      capture was cut before it.", file=sys.stderr)
    if not entries:
        print("NO TRACE IN THIS CAPTURE.", file=sys.stderr)
        print("  The trace is dumped once, after the stall detector fires, and it is long:", file=sys.stderr)
        print("  give the capture enough time (a full 8192-entry ring is about 17 s at 115200).", file=sys.stderr)
        print("  If the machine never stalled, nothing is dumped at all - that is correct", file=sys.stderr)
        print("  behaviour, not a fault, and the watchdog message is the only output.", file=sys.stderr)
        return 1

    pack = None
    if args.pack.is_file():
        pack = args.pack.read_bytes()
    else:
        print(f"note: no pack at {args.pack}, so no instruction bytes are shown", file=sys.stderr)

    print(f"{len(entries)} entries, oldest first. The LAST one is where the guest stopped.")
    print(f"bank assumption: {args.bank} in the 0xF8000 window (port 0x043F is not in the trace)")
    print()
    print("  #     CS:EIP            linear    dwell   bytes at the address")
    for i, (cs, eip, dwell) in enumerate(entries):
        linear = (cs << 4) + eip
        off = pack_offset(linear, args.bank)
        if pack is not None and off is not None and 0 <= off < len(pack):
            shown = pack[off:off + args.bytes]
            hexed = " ".join(f"{b:02X}" for b in shown)
        else:
            hexed = ("(not in a ROM window)" if off is None
                     else "(outside the pack)")
        mark = ""
        if dwell == WEDGED_DWELL:
            mark = "  <== NEVER LEFT: the stall is here"
        print(f"  {i:5d} {cs:04X}:{eip:08X}   {linear:08X}  {dwell:5d}   {hexed}{mark}")
    print()
    last_cs, last_eip, last_dwell = entries[-1]
    if last_dwell == WEDGED_DWELL:
        print(f"The guest stopped at {last_cs:04X}:{last_eip:08X} "
              f"(linear {(last_cs << 4) + last_eip:08X}) and never left it.")
        print("If the preceding entries form a small cycle of the same few PCs, that cycle is "
              "the retry loop it is spinning in.")
    else:
        print(f"The trace ended at {last_cs:04X}:{last_eip:08X} with dwell {last_dwell}, which is "
              "NOT the stall marker. Either this is not the dumped trace's end, or the capture "
              "was cut short.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
