set script_dir [file dirname [file normalize [info script]]]
set board_dir [file normalize [file join $script_dir ..]]
set cpu_dir [file normalize [file join $board_dir ../..]]
set enable_x87 [expr {[llength $argv] > 0 && [lindex $argv 0] eq "1"}]
set cpu_mhz [expr {[llength $argv] > 1 ? [lindex $argv 1] : 100}]

if {![string is integer -strict $cpu_mhz] || $cpu_mhz < 1 || $cpu_mhz > 127} {
    error "CPU frequency must be an integer from 1 through 127 MHz"
}

set suffix [expr {$enable_x87 ? "-x87" : ""}]
set build_dir [file join $board_dir "build-cpu${suffix}"]
set period_ns [expr {1000.0 / double($cpu_mhz)}]
file mkdir $build_dir
foreach image [list \
        [file join $cpu_dir ucode.hex] \
        [file join $cpu_dir pla_entry_rom.hex] \
        [file join $cpu_dir pla_group_entry.hex] \
        [file join $cpu_dir x87 x87_ucode.mem]] {
    file copy -force $image [file join $build_dir [file tail $image]]
}

set manifest [file join $cpu_dir boards common rtl_sources.f]
set manifest_file [open $manifest r]
while {[gets $manifest_file line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
        continue
    }
    # The demo-only files at the tail are harmless, but excluding them makes
    # the CPU-only source set and reports easier to audit.
    if {[string match "boards/common/*" $line]} {
        continue
    }
    read_verilog -sv [file join $cpu_dir $line]
}
close $manifest_file

set constraints_file [file join $build_dir cpu_ooc.xdc]
set constraints [open $constraints_file w]
puts $constraints [format {create_clock -name cpu_clk -period %.6f [get_ports clk]} \
    $period_ns]
puts $constraints {set_false_path -from [get_ports reset_n]}
puts $constraints {set_input_delay -clock cpu_clk 0.0 [get_ports {din[*] ready resp_valid intr nmi snoop_addr[*] snoop_valid a20_enable win0_unmapped ram_cache_top[*] cpu_speed_sel[*] single_step}]}
puts $constraints {set_output_delay -clock cpu_clk 0.0 [get_ports {addr[*] be[*] burstcount[*] dout[*] valid write io inta dbg_CS[*] dbg_EIP[*] dbg_CS_base[*] dbg_pe dbg_vm dbg_x87_state[*] triple_fault_reset}]}
close $constraints
read_xdc $constraints_file

# Keep synthesis and implementation in the same non-project OOC design. A
# project implementation run would relink the checkpoint as a package-level
# top and incorrectly require 268 physical I/O pins.
cd $build_dir
synth_design -top z486 -part xck26-sfvc784-2LV-c -mode out_of_context \
    -include_dirs [list $cpu_dir [file join $cpu_dir x87]] \
    -define Z486_XILINX=1 -generic "ENABLE_X87=$enable_x87" \
    -generic "CLOCK_RATE_MHZ=$cpu_mhz"
write_checkpoint -force [file join $build_dir z486_cpu_synth.dcp]
report_utilization -hierarchical -file \
    [file join $build_dir utilization_synth.rpt]

opt_design -directive Explore
place_design -directive Explore
phys_opt_design -directive Explore
route_design -directive Explore
phys_opt_design -directive Explore

report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
report_timing -delay_type max -from [all_registers] -to [all_registers] \
    -max_paths 20 -path_type full_clock_expanded \
    -file [file join $build_dir timing_internal.rpt]
report_utilization -hierarchical -file [file join $build_dir utilization.rpt]
report_drc -file [file join $build_dir drc.rpt]
write_checkpoint -force [file join $build_dir z486_cpu_routed.dcp]
