set script_dir [file dirname [file normalize [info script]]]
set board_dir [file normalize [file join $script_dir ..]]
set cpu_dir [file normalize [file join $board_dir ../..]]
set build_dir [file join $board_dir build]
set project_name z486_kv260

file mkdir $build_dir
create_project $project_name $build_dir -force -part xck26-sfvc784-2LV-c
set_property board_part xilinx.com:kv260_som:part0:1.4 [current_project]
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property include_dirs [list $cpu_dir [file join $cpu_dir x87]] \
    [get_filesets sources_1]
set_property verilog_define {Z486_XILINX=1} [get_filesets sources_1]

set manifest [file join $cpu_dir boards common rtl_sources.f]
set manifest_file [open $manifest r]
while {[gets $manifest_file line] >= 0} {
    set line [string trim $line]
    if {$line eq "" || [string match "#*" $line]} {
        continue
    }
    add_files -norecurse [file join $cpu_dir $line]
}
close $manifest_file

add_files -norecurse [file join $board_dir rtl kv260_top.sv]
add_files -fileset constrs_1 -norecurse \
    [file join $board_dir constraints kv260.xdc]

foreach image [list \
        [file join $cpu_dir ucode.hex] \
        [file join $cpu_dir pla_entry_rom.hex] \
        [file join $cpu_dir pla_group_entry.hex] \
        [file join $cpu_dir x87 x87_ucode.mem] \
        [file join $cpu_dir boards firmware blink.hex]] {
    add_files -norecurse $image
    set_property file_type {Memory Initialization Files} [get_files $image]
}

create_bd_design system
set ps [create_bd_cell -type ip -vlnv xilinx.com:ip:zynq_ultra_ps_e:* ps]
apply_bd_automation -rule xilinx.com:bd_rule:zynq_ultra_ps_e \
    -config {apply_board_preset "1"} $ps
set_property -dict [list \
    CONFIG.PSU__FPGA_PL0_ENABLE {1} \
    CONFIG.PSU__CRL_APB__PL0_REF_CTRL__FREQMHZ {100} \
    CONFIG.PSU__USE__M_AXI_GP0 {0} \
    CONFIG.PSU__USE__M_AXI_GP1 {0} \
    CONFIG.PSU__USE__M_AXI_GP2 {0}] $ps

set clk_wiz [create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:* cpu_clock]
set_property -dict [list \
    CONFIG.PRIM_IN_FREQ {99.999001} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {100.000} \
    CONFIG.USE_RESET {false}] $clk_wiz

set reset_and [create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:* reset_and]
set_property -dict [list CONFIG.C_OPERATION {and} CONFIG.C_SIZE {1}] $reset_and

connect_bd_net [get_bd_pins ps/pl_clk0] [get_bd_pins cpu_clock/clk_in1]
connect_bd_net [get_bd_pins ps/pl_resetn0] [get_bd_pins reset_and/Op1]
connect_bd_net [get_bd_pins cpu_clock/locked] [get_bd_pins reset_and/Op2]

set cpu_clk_port [create_bd_port -dir O -type clk -freq_hz 99999001 cpu_clk]
set cpu_reset_port [create_bd_port -dir O -type rst cpu_arst_n]
set_property CONFIG.POLARITY ACTIVE_LOW $cpu_reset_port
connect_bd_net [get_bd_pins cpu_clock/clk_out1] $cpu_clk_port
connect_bd_net [get_bd_pins reset_and/Res] $cpu_reset_port

validate_bd_design
save_bd_design
set bd_file [get_files */system.bd]
generate_target all $bd_file
set wrapper [make_wrapper -files $bd_file -top]
add_files -norecurse $wrapper

set_property top kv260_top [get_filesets sources_1]
update_compile_order -fileset sources_1

set_property strategy Flow_PerfOptimized_high [get_runs synth_1]
set_property strategy Performance_Explore [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} {
    error "implementation did not complete"
}

open_run impl_1
report_timing_summary -delay_type min_max -report_unconstrained \
    -check_timing_verbose -file [file join $build_dir timing_summary.rpt]
report_utilization -hierarchical -file [file join $build_dir utilization.rpt]
report_drc -file [file join $build_dir drc.rpt]
write_hw_platform -fixed -include_bit -force \
    [file join $build_dir z486_kv260.xsa]
