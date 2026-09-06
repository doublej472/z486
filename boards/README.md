# z486 board demos

These minimal designs show how to deploy the `z486` CPU on Altera DE10-Nano
and Xilinx KV260. Both boards run the same 16-bit x86 firmware from
`firmware/blink.asm`. The firmware writes `55`, `aa`, `55`, ... to I/O port
`0x80`, driving the onboard LEDs of the DE10-Nano or a PMOD LED module on the
KV260.

## Prerequisites

- Verilator 5.x, GNU Make, and a C++ compiler for `make sim`.
- NASM and standard Unix tools (`od`, `sed`, and `wc`) to build the shared x86
  firmware.
- Vivado 2024.2 with KV260/K26 device and board support for `make kv260` and
  Vivado Simulator for `make kv260-sim`. Override its location with
  `VIVADO=/path/to/vivado` when needed.
- Quartus Prime Lite 17.0 with Cyclone V support for `make de10nano`. Override
  its installation directory with `QUARTUS_ROOTDIR=/path/to/quartus` when
  needed.

The reference builds were verified with Verilator 5.044, Vivado 2024.2.2, and
Quartus Prime Lite 17.0.2.

## Layout

- `firmware/` contains the x86 source and the generated 64 KiB BIOS ROM.
- `common/` contains the portable ROM/bus target and self-checking simulation.
- `kv260/` contains the Xilinx top level, PMOD constraints, and Vivado build.
- `de10nano/` contains the Altera top level, onboard-LED constraints, and
  Quartus build.

## Simulation

```bash
make sim
```

The test boots through physical address `0xfffffff0`, follows the far jump to
the ROM alias at `0x000f0000`, and passes after observing `55`, `aa`, `55` from
CPU I/O writes.

To exercise the Xilinx-specific RTL branches with Vivado Simulator, run:

```bash
make kv260-sim
```

This runs the same firmware source through `xvlog`, `xelab`, and `xsim` with
`Z486_XILINX` and x87 enabled. It shortens only the firmware delay loop; the
test still boots at the architectural reset vector and follows the far jump to
the ROM alias before checking the `55`, `aa`, `55` I/O writes.

## DE10-Nano

The DE10-Nano demo drives the eight onboard LEDs.

```bash
make de10nano
```

Then use Quartus Programmer to program
`de10nano/build/output_files/z486_de10nano.sof` to the board.

## KV260

For KV260, the carrier board has no
PL-connected user LEDs, so connect an eight-LED PMOD to J2, and this design will drive that.

```bash
make kv260
```

For quick testing, use Vivado Hardware Manager to program
`kv260/build/z486_kv260.runs/impl_1/kv260_top.bit` over JTAG. For managed
loading under Ubuntu, build an `xmutil` application package and copy it to the
board:

```bash
make kv260-package
ssh root@z486 'mkdir -p /lib/firmware/xilinx'
scp -r kv260/build/app/z486-led root@z486:/lib/firmware/xilinx/
```

Then load the LED demo:

```bash
xmutil unloadapp
xmutil loadapp z486-led
```

## CPU area and timing

These are post-fit/post-route results for the CPU hierarchy inside each
complete board demo, with x87 and the default 8 KiB instruction and data
caches enabled:

| Board | Configuration | Timing | Logic | Registers | Memory | DSPs |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| DE10-Nano | CPU + x87 | 57.95 MHz Fmax | 24,411.3 ALMs | 15,696 | 92 M10Ks | 12 |
| KV260 | CPU + x87 | 100 MHz, +0.441 ns setup slack | 41,290 LUTs | 13,036 | 20 RAMB36 + 11 RAMB18 | 19 |

The DE10-Nano line comes from `make de10nano-fmax`, which uses an 85 MHz PLL
and the `z486_MiSTer` production optimization profile to drive the fitter. The
KV260 line comes from a clean full `make kv260` implementation at 100 MHz
after the XSim declaration-order fixes in commit `13f29b2e`. The complete
KV260 LED design uses 41,322 LUTs, 13,074 registers, 36 RAMB36 plus 11 RAMB18,
and 19 DSPs; 16 of those RAMB36 blocks hold the 64 KiB demonstration firmware
rather than CPU state.

## Portability selection

The KV260 build defines `Z486_XILINX`; the DE10-Nano build defines
`Z486_ALTERA`. A generic simulation defines neither. `z486_platform.svh`
normalizes those selections and the legacy MiSTer macros into feature-specific
memory, ALU, and synthesis-attribute choices.
