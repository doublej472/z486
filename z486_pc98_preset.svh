// z486 PC-98 memory-map preset; splice `Z486_PC98_MAP_PARAMS into a `z486
// parameter list. VGA_BASE/VGA_TOP default to A0000-BFFFF. The no-allocate
// bound defaults to the 128 MiB L1 tag reach; use
// `Z486_PC98_MAP_PARAMS_BOUND(bound) to pass a lower bound, such as the RAM top.
`ifndef Z486_PC98_PRESET_SVH
`define Z486_PC98_PRESET_SVH

`define Z486_PC98_NO_ALLOC_BOUND 32'h0800_0000

// The A20 mask with A20 off: bit 20 cleared and nothing else. The PC-9821's
// A20 gate (ports F2h/F6h) drives the 486's A20M#; measured on a real Xe10
// (A20MAP: with A20 masked, X+1M aliases X and X+3M aliases X+2M, while X+2M
// and X+16M keep their own cells). The 1 MiB wrap this preset used before
// (NP2kai's model) folded masked accesses above 2 MiB - including the page
// walker's - onto low memory. Exported so a bench instantiates the same value
// (tests/programs/pc98_a20_bit20).
`define Z486_PC98_A20_MASK_OFF 32'hffef_ffff

`define Z486_PC98_MAP_PARAMS_BOUND(bound) \
    .A20_MASK_OFF    (`Z486_PC98_A20_MASK_OFF), \
    .VGA_ENABLE      (1'b1), \
    .VGA_PRE_WRAP    (1'b0), \
    .APERTURE_ENABLE (1'b1), \
    .ALIAS_ENABLE    (1'b1), \
    .WIN0_ENABLE     (1'b1), \
    .NO_ALLOC_ENABLE (1'b1), \
    .NO_ALLOC_BOUND  (bound)

`define Z486_PC98_MAP_PARAMS `Z486_PC98_MAP_PARAMS_BOUND(`Z486_PC98_NO_ALLOC_BOUND)

`endif
