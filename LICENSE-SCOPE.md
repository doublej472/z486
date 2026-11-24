# License Scope

The Apache License, Version 2.0, in [LICENSE](LICENSE) applies only to files
in this repository with the following extensions:

- SystemVerilog source: `*.sv` and `*.svh`
- Python source: `*.py`
- Documentation: `*.md`

`ucode.hex` is excluded from the Apache License 2.0 grant.

`tests/lockstep/` is excluded from the Apache License 2.0 grant: every file in
that directory, whatever its extension, is licensed under the GNU General
Public License, version 3 or later, in
[tests/lockstep/LICENSE](tests/lockstep/LICENSE). It is a test-only harness
that links the GPL-3 86Box reference model (fetched by its build script, not
included here) and follows Tetrium's GPL-3 testbench. Nothing in it is part of
the synthesized CPU: no RTL file includes, instantiates or depends on it.
