#!/usr/bin/env python3
"""Build the freestanding Dhrystone image with Open Watcom under DOSBox."""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
from pathlib import Path


THIS_DIR = Path(__file__).resolve().parent
REPO_ROOT = THIS_DIR.parents[2]
DEFAULT_WATCOM = REPO_ROOT / "dos" / "WATCOM"

PROFILE_OPTIONS = {
    "optimized": "-ox",
    "noopt": "-od",
}

STAGED_SOURCES = {
    "dhry.h": "dhry.h",
    "dhry_1.c": "dhry_1.c",
    "dhry_2.c": "dhry_2.c",
    "support.c": "support.c",
    "dhrystone_main.c": "main.c",
    "startup_watcom.asm": "startup.asm",
    "watcom.lnk": "watcom.lnk",
    "watcom_build.bat": "build.bat",
}


def generate_linked_listing(build_dir: Path, objdump: str) -> Path:
    """Add Watcom map symbols to a linked raw-binary disassembly."""
    map_file = build_dir / "DHRY.MAP"
    binary = build_dir / "DHRY.BIN"
    map_text = map_file.read_text(errors="replace")
    text_match = re.search(
        r"^_TEXT\s+CODE\s+AUTO\s+[0-9A-Fa-f]+\s+([0-9A-Fa-f]+)",
        map_text,
        re.MULTILINE,
    )
    if text_match is None:
        raise RuntimeError(f"could not find the _TEXT segment in {map_file}")
    text_size = int(text_match.group(1), 16)

    symbols: dict[int, list[str]] = {}
    symbol_re = re.compile(r"^([0-9A-Fa-f]{8})[+*]?\s+(\S+)\s*$")
    for line in map_text.splitlines():
        match = symbol_re.match(line)
        if match is None:
            continue
        address = int(match.group(1), 16)
        if address >= text_size:
            continue
        name = match.group(2)
        if name.endswith("_"):
            name = name[:-1]
        symbols.setdefault(address, []).append(name)

    disassembly = subprocess.run(
        [objdump, "-D", "-b", "binary", "-m", "i386", "-Mintel", str(binary)],
        text=True,
        capture_output=True,
        check=True,
    ).stdout
    instruction_re = re.compile(r"^\s*([0-9A-Fa-f]+):")
    output: list[str] = []
    emitted: set[int] = set()
    for line in disassembly.splitlines():
        match = instruction_re.match(line)
        if match is not None:
            address = int(match.group(1), 16)
            if address in symbols and address not in emitted:
                output.append("")
                for name in symbols[address]:
                    output.append(f"{address:08x} <{name}>:")
                emitted.add(address)
        output.append(line)

    listing = build_dir / "dhrystone.lst"
    listing.write_text("\n".join(output) + "\n")
    return listing


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--iters", type=int, default=200)
    parser.add_argument(
        "--profile", choices=tuple(PROFILE_OPTIONS), default="optimized"
    )
    parser.add_argument("--watcom-dir", type=Path, default=DEFAULT_WATCOM)
    parser.add_argument("--dosbox", default="dosbox")
    parser.add_argument("--objdump", default="objdump")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    watcom_dir = args.watcom_dir.resolve()
    compiler = watcom_dir / "BINW" / "WCC386.EXE"
    linker = watcom_dir / "BINW" / "WLINK.EXE"
    if not compiler.is_file() or not linker.is_file():
        parser.error(
            f"Open Watcom DOS tools were not found below {args.watcom_dir}; "
            "pass --watcom-dir or install them under dos/WATCOM"
        )
    dosbox = shutil.which(args.dosbox)
    if dosbox is None:
        parser.error(f"DOSBox executable not found: {args.dosbox}")
    objdump = shutil.which(args.objdump)
    if objdump is None:
        parser.error(f"objdump executable not found: {args.objdump}")

    build_dir = THIS_DIR / "build" / "watcom" / args.profile
    build_dir.mkdir(parents=True, exist_ok=True)
    for source_name, staged_name in STAGED_SOURCES.items():
        shutil.copy2(THIS_DIR / source_name, build_dir / staged_name)

    success_file = build_dir / "SUCCESS.OK"
    success_file.unlink(missing_ok=True)
    command = [
        dosbox,
        "-c", f"mount c {build_dir}",
        "-c", f"mount w {watcom_dir}",
        "-c", "set WATCOM=W:\\",
        "-c", "set PATH=W:\\BINW",
        "-c", "c:",
        "-c", f"call build.bat {args.iters} {PROFILE_OPTIONS[args.profile]}",
        "-c", "exit",
    ]
    env = os.environ.copy()
    env.setdefault("SDL_VIDEODRIVER", "dummy")
    env.setdefault("SDL_AUDIODRIVER", "dummy")
    result = subprocess.run(
        command,
        cwd=THIS_DIR,
        env=env,
        text=True,
        capture_output=not args.verbose,
        timeout=120,
    )
    if result.returncode != 0 or not success_file.exists():
        if not args.verbose:
            print(result.stdout)
            print(result.stderr)
        raise RuntimeError("Open Watcom build failed (SUCCESS.OK was not produced)")

    binary = build_dir / "DHRY.BIN"
    if not binary.is_file():
        raise RuntimeError(f"Open Watcom did not produce {binary}")
    listing = generate_linked_listing(build_dir, objdump)
    print(f"Open Watcom profile: {args.profile}")
    print(f"Dhrystone iterations: {args.iters}")
    print(f"Binary: {binary.relative_to(THIS_DIR)} ({binary.stat().st_size} bytes)")
    print(f"Listing: {listing.relative_to(THIS_DIR)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
