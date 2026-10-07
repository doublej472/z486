# Makefile for z486 testing
#
# Builds and runs single-instruction tests for the z486 core

# Paths
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
Z486_DIR := ..
VERILATOR := verilator
JOBS ?= 8

# Source files
# Note: muldiv.sv and bus_prefetch.sv are standalone modules that can optionally
# replace the inline mul/div and bus/prefetch code in z486.sv.
# Currently z486.sv uses inline code; uncomment modules below when integrating.
X87_DIR := $(Z486_DIR)/x87
X87_REF_DIR := x87_reference
X87_UCODE_GEN := $(X87_DIR)/x87_ucode.svh \
			$(X87_DIR)/x87_ucode.mif \
			$(X87_DIR)/x87_ucode.mem \
			$(X87_DIR)/x87_entries.svh
X87_COMMAND_GEN := $(X87_DIR)/x87_command_decode.svh \
			$(X87_DIR)/x87_command_decode.mif
X87_LOGEXP_GEN := $(X87_DIR)/x87_logexp_tables.svh \
			$(X87_DIR)/x87_logexp_tables.mif
X87_GEN := $(X87_UCODE_GEN) $(X87_COMMAND_GEN) $(X87_LOGEXP_GEN)
X87_RTL := $(X87_DIR)/x87_pkg.sv \
			$(X87_DIR)/x87_ucode_pkg.sv \
			$(X87_DIR)/x87_bridge.sv \
			$(X87_DIR)/x87_cordic_rom.sv \
			$(X87_DIR)/x87_cordic_scratch.sv \
			$(X87_DIR)/x87_ucode_rom.sv \
			$(X87_DIR)/x87_sequencer.sv \
			$(X87_DIR)/x87_executor.sv \
			$(X87_DIR)/x87_transfer_fifo.sv \
			$(X87_DIR)/x87_stack_mem.sv \
			$(X87_DIR)/x87_command_rom.sv \
			$(X87_DIR)/x87_control.sv \
			$(X87_DIR)/x87_unit.sv

RTL_SRCS := $(Z486_DIR)/z486_pkg.sv $(Z486_DIR)/z486_cache_map_pkg.sv $(X87_DIR)/x87_pkg.sv \
			$(X87_DIR)/x87_ucode_pkg.sv $(Z486_DIR)/z486.sv \
			$(Z486_DIR)/cpu_throttle.sv $(Z486_DIR)/interrupt_controller.sv \
			$(Z486_DIR)/ucode_rom.sv $(Z486_DIR)/microsequencer.sv $(Z486_DIR)/event_control.sv $(Z486_DIR)/hardwired_control.sv $(Z486_DIR)/data_access.sv \
			$(Z486_DIR)/data_unit.sv $(Z486_DIR)/gpr_write_merge.sv $(Z486_DIR)/address_unit.sv \
			$(Z486_DIR)/shifter.sv $(Z486_DIR)/mul_div.sv \
			$(Z486_DIR)/decoder.sv \
			$(Z486_DIR)/alu.sv $(Z486_DIR)/prefetch.sv \
			$(Z486_DIR)/paging_unit.sv $(Z486_DIR)/paging_tlb.sv $(Z486_DIR)/paging_walker.sv \
			$(Z486_DIR)/memory.sv $(Z486_DIR)/bus_unit.sv $(Z486_DIR)/cache_unit.sv $(Z486_DIR)/l1_cache.sv $(Z486_DIR)/l1_icache.sv \
			$(filter-out $(X87_DIR)/x87_pkg.sv $(X87_DIR)/x87_ucode_pkg.sv,$(X87_RTL)) \
			$(Z486_DIR)/dsp_mul.sv $(Z486_DIR)/protection.sv $(Z486_DIR)/segmentation_unit.sv
RTL_DEPS := $(Z486_DIR)/ucode_recipes.svh $(Z486_DIR)/pb_b1_class.svh \
            $(Z486_DIR)/z486_platform.svh \
            $(Z486_DIR)/z486_pc98_preset.svh $(Z486_DIR)/pla_entry.svh \
            $(Z486_DIR)/pla_control.svh $(Z486_DIR)/length_table.svh \
            $(Z486_DIR)/ucode.hex $(Z486_DIR)/pla_entry_rom.hex \
            $(Z486_DIR)/pla_group_entry.hex $(X87_GEN) \
			$(X87_DIR)/x87_logexp_rom.sv
# Optional modules (not yet integrated):
# RTL_SRCS += $(Z486_DIR)/muldiv.sv $(Z486_DIR)/bus_prefetch.sv
TB_SRCS := tb_z486.sv
CPP_SRCS := sim_main.cpp

# Verilator flags (common, no --top-module — set per target)
VFLAGS_BASE := --timing
VFLAGS_BASE += -Wall -Wno-fatal -Wno-UNOPTFLAT -Wno-SYNCASYNCNET
VFLAGS_BASE += -cc --exe
VFLAGS_BASE += -O3
VFLAGS_BASE += --build
VFLAGS_BASE += -j $(JOBS)
VFLAGS_BASE += -I$(Z486_DIR)
VFLAGS_BASE += -I$(X87_DIR)
VFLAGS_BASE += -I$(X87_REF_DIR)
VFLAGS_BASE += -CFLAGS "-std=c++14 -O3"

# With VCD trace support (singlestep tests — short runs, need waveforms)
VFLAGS := $(VFLAGS_BASE) --trace --trace-structs
# With FST trace (test386/test186 — millions of cycles, FST is compact)
VFLAGS_FST := $(VFLAGS_BASE) --trace-fst
# Without trace (default test386/test186 build)
VFLAGS_NOTRACE := $(VFLAGS_BASE)

# test386 testbench sources
TB386_SRCS := tb_test386.sv
CPP386_SRCS := sim_main_test386.cpp

# test186 testbench sources (80186 test suite)
TB186_SRCS := tb_test186.sv
CPP186_SRCS := sim_main_test186.cpp

# protected mode testbench sources
TB_PROT_SRCS := tb_protected_mode.sv
TB_PROT_DEPS := m0_profile.svh   # included by the testbench: prerequisite only
CPP_PROT_SRCS := sim_main_protected_mode.cpp
CPP_QUAKE_SNAPSHOT_SRCS := sim_main_quake_snapshot.cpp

# L1 cache unit test
TB_L1_SRCS := tb_l1_cache.sv
CPP_L1_SRCS := sim_main_l1_cache.cpp
TB_L1I_SRCS := tb_l1_icache.sv
CPP_L1I_SRCS := sim_main_l1_icache.cpp
TB_MEMORY_ORDER_SRCS := tb_memory_order.sv
CPP_MEMORY_ORDER_SRCS := sim_main_memory_order.cpp
TB_LOAD_WAW_SRCS := tb_load_waw.sv
CPP_LOAD_WAW_SRCS := sim_main_load_waw.cpp
TB_GPR_HAZARD_SRCS := tb_gpr_hazard.sv
CPP_GPR_HAZARD_SRCS := sim_main_gpr_hazard.cpp
TB_GPR_MERGE_SRCS := tb_gpr_write_merge.sv
CPP_GPR_MERGE_SRCS := sim_main_gpr_write_merge.cpp
# data_unit plus its sub-units; the bench drives the deferred GPR write ports
# directly and needs no cache, bus or sequencer.
LOAD_WAW_RTL := $(Z486_DIR)/data_unit.sv $(Z486_DIR)/gpr_write_merge.sv $(Z486_DIR)/alu.sv $(Z486_DIR)/shifter.sv \
			$(Z486_DIR)/mul_div.sv $(Z486_DIR)/dsp_mul.sv
TB_MEMMAP_SRCS := tb_memmap_template.sv
CPP_MEMMAP_SRCS := sim_main_memmap_template.cpp
TB_INTERRUPT_NMI_SRCS := tb_interrupt_nmi.sv
TB_PAGING_WALKER_SRCS := tb_paging_walker.sv
TB_CACHE_FLUSH_SRCS := tb_cache_flush.sv
TB_X87_BRIDGE_SRCS := tb_x87_bridge.sv
CPP_X87_BRIDGE_SRCS := sim_main_x87_bridge.cpp
TB_X87_SEQ_SRCS := tb_x87_sequencer.sv
CPP_X87_SEQ_SRCS := sim_main_x87_sequencer.cpp
TB_X87_EXECUTOR_SRCS := tb_x87_executor.sv
CPP_X87_EXECUTOR_SRCS := sim_main_x87_executor.cpp
TB_X87_TESTFLOAT_SRCS := tb_x87_testfloat.sv
CPP_X87_TESTFLOAT_SRCS := sim_main_x87_testfloat.cpp
TB_X87_CORE_SRCS := tb_x87_core.sv
CPP_X87_CORE_SRCS := sim_main_x87_core.cpp
TB_X87_FIFO_SRCS := tb_x87_transfer_fifo.sv
CPP_X87_FIFO_SRCS := sim_main_x87_transfer_fifo.cpp

# PLA4 verification testbench sources
TB_PLA4_SRCS := tb_protection_pla4.sv
CPP_PLA4_SRCS := sim_main_pla4.cpp
PLA4_RTL := $(Z486_DIR)/protection.sv

# Targets
.PHONY: all build test-simple test-full test-386 test-186 test-protected test-pla4 test-l1-cache test-l1-icache test-memory-order test-load-waw test-gpr-hazard test-gpr-merge test-memmap-template check-reset-lists check-pragmas check-rom-columns check-shift-ucode test-interrupt-nmi test-paging-walker test-cache-flush test-x87-bridge test-x87-sequencer test-x87-executor test-x87-testfloat test-x87-fifo test-x87-core test-x87-integration test-x87-integer dhrystone clean help

all: build

# Build all testbenches
build: obj_dir/Vtb_z486 obj_dir/Vtb_protected_mode

obj_dir/Vtb_z486: $(RTL_SRCS) $(RTL_DEPS) $(TB_SRCS) $(CPP_SRCS)
	@echo "Building z486 testbench with Verilator..."
	cp -f ../*.hex .
	$(VERILATOR) $(VFLAGS) --top-module tb_z486 $(TB_SRCS) $(RTL_SRCS) $(CPP_SRCS)
	@echo "Build complete: obj_dir/Vtb_z486"

obj_dir/Vtb_protected_mode: $(RTL_SRCS) $(RTL_DEPS) $(TB_PROT_SRCS) $(TB_PROT_DEPS) $(CPP_PROT_SRCS)
	@echo "Building protected mode testbench with Verilator..."
	cp -f ../*.hex .
	$(VERILATOR) $(VFLAGS) --top-module tb_protected_mode $(TB_PROT_SRCS) $(RTL_SRCS) $(CPP_PROT_SRCS)
	@echo "Build complete: obj_dir/Vtb_protected_mode"

obj_dir_x87/Vtb_protected_mode: $(RTL_SRCS) $(RTL_DEPS) $(TB_PROT_SRCS) $(TB_PROT_DEPS) $(CPP_PROT_SRCS)
	@echo "Building x87-enabled protected mode testbench with Verilator..."
	cp -f ../*.hex .
	$(VERILATOR) $(VFLAGS) --Mdir obj_dir_x87 -GENABLE_X87=1 --top-module tb_protected_mode \
		$(TB_PROT_SRCS) $(RTL_SRCS) $(CPP_PROT_SRCS)
	@echo "Build complete: obj_dir_x87/Vtb_protected_mode"

obj_dir_quake/Vtb_protected_mode: $(RTL_SRCS) $(RTL_DEPS) $(TB_PROT_SRCS) $(TB_PROT_DEPS) $(CPP_QUAKE_SNAPSHOT_SRCS)
	@echo "Building 64MB workload snapshot replay..."
	cp -f ../*.hex .
	$(VERILATOR) $(VFLAGS_NOTRACE) --Mdir obj_dir_quake \
		-GENABLE_X87=1 -GMEM_SIZE=67108864 --top-module tb_protected_mode \
		$(TB_PROT_SRCS) $(RTL_SRCS) $(CPP_QUAKE_SNAPSHOT_SRCS)
	@echo "Build complete: obj_dir_quake/Vtb_protected_mode"

obj_dir_quake_trace/Vtb_protected_mode: $(RTL_SRCS) $(RTL_DEPS) $(TB_PROT_SRCS) $(TB_PROT_DEPS) $(CPP_QUAKE_SNAPSHOT_SRCS)
	@echo "Building trace-enabled 64MB workload snapshot replay..."
	cp -f ../*.hex .
	$(VERILATOR) $(VFLAGS_FST) --Mdir obj_dir_quake_trace \
		-GENABLE_X87=1 -GMEM_SIZE=67108864 --top-module tb_protected_mode \
		$(TB_PROT_SRCS) $(RTL_SRCS) $(CPP_QUAKE_SNAPSHOT_SRCS)
	@echo "Build complete: obj_dir_quake_trace/Vtb_protected_mode"

obj_dir_x87_int/Vtb_z486: $(RTL_SRCS) $(RTL_DEPS) $(TB_SRCS) $(CPP_SRCS)
	@echo "Building x87-enabled integer testbench with Verilator..."
	cp -f ../*.hex .
	$(VERILATOR) $(VFLAGS) --Mdir obj_dir_x87_int -GENABLE_X87=1 --top-module tb_z486 \
		$(TB_SRCS) $(RTL_SRCS) $(CPP_SRCS)
	@echo "Build complete: obj_dir_x87_int/Vtb_z486"

obj_dir/Vtb_test386: $(RTL_SRCS) $(RTL_DEPS) $(TB386_SRCS) $(CPP386_SRCS)
	@echo "Building test386 testbench with Verilator..."
	cp -f ../*.hex .
	$(VERILATOR) $(VFLAGS_FST) --top-module tb_test386 $(TB386_SRCS) $(RTL_SRCS) $(CPP386_SRCS)
	@echo "Build complete: obj_dir/Vtb_test386"

obj_dir/Vtb_l1_cache: $(Z486_DIR)/l1_cache.sv $(TB_L1_SRCS) $(CPP_L1_SRCS)
	@echo "Building L1 cache unit test with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --top-module tb_l1_cache $(TB_L1_SRCS) $(Z486_DIR)/l1_cache.sv $(CPP_L1_SRCS)
	@echo "Build complete: obj_dir/Vtb_l1_cache"

obj_dir/Vtb_l1_icache: $(Z486_DIR)/l1_icache.sv $(TB_L1I_SRCS) $(CPP_L1I_SRCS)
	@echo "Building L1 instruction cache unit test with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --top-module tb_l1_icache $(TB_L1I_SRCS) $(Z486_DIR)/l1_icache.sv $(CPP_L1I_SRCS)
	@echo "Build complete: obj_dir/Vtb_l1_icache"

obj_dir/Vtb_memory_order: $(Z486_DIR)/z486_cache_map_pkg.sv $(Z486_DIR)/z486_pkg.sv $(RTL_DEPS) $(Z486_DIR)/memory.sv $(Z486_DIR)/bus_unit.sv $(Z486_DIR)/cache_unit.sv $(Z486_DIR)/l1_cache.sv $(Z486_DIR)/l1_icache.sv $(TB_MEMORY_ORDER_SRCS) $(CPP_MEMORY_ORDER_SRCS)
	@echo "Building memory ordering unit test with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --top-module tb_memory_order $(Z486_DIR)/z486_pkg.sv $(Z486_DIR)/z486_cache_map_pkg.sv $(TB_MEMORY_ORDER_SRCS) \
		$(Z486_DIR)/memory.sv $(Z486_DIR)/bus_unit.sv $(Z486_DIR)/cache_unit.sv $(Z486_DIR)/l1_cache.sv $(Z486_DIR)/l1_icache.sv $(CPP_MEMORY_ORDER_SRCS)
	@echo "Build complete: obj_dir/Vtb_memory_order"

obj_dir/Vtb_load_waw: $(Z486_DIR)/z486_pkg.sv $(LOAD_WAW_RTL) $(TB_LOAD_WAW_SRCS) $(CPP_LOAD_WAW_SRCS)
	@echo "Building same-cycle load write-arbitration unit test with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --top-module tb_load_waw $(TB_LOAD_WAW_SRCS) \
		$(Z486_DIR)/z486_pkg.sv $(LOAD_WAW_RTL) $(CPP_LOAD_WAW_SRCS)
	@echo "Build complete: obj_dir/Vtb_load_waw"

obj_dir/Vtb_gpr_hazard: $(Z486_DIR)/z486_pkg.sv $(LOAD_WAW_RTL) $(TB_GPR_HAZARD_SRCS) $(CPP_GPR_HAZARD_SRCS)
	@echo "Building GPR hazard survey bench with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --top-module tb_gpr_hazard $(TB_GPR_HAZARD_SRCS) \
		$(Z486_DIR)/z486_pkg.sv $(LOAD_WAW_RTL) $(CPP_GPR_HAZARD_SRCS)
	@echo "Build complete: obj_dir/Vtb_gpr_hazard"

obj_dir/Vtb_gpr_write_merge: $(Z486_DIR)/z486_pkg.sv $(Z486_DIR)/gpr_write_merge.sv $(TB_GPR_MERGE_SRCS) $(CPP_GPR_MERGE_SRCS)
	@echo "Building GPR write-merge unit bench with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --top-module tb_gpr_write_merge $(TB_GPR_MERGE_SRCS) \
		$(Z486_DIR)/z486_pkg.sv $(Z486_DIR)/gpr_write_merge.sv $(CPP_GPR_MERGE_SRCS)
	@echo "Build complete: obj_dir/Vtb_gpr_write_merge"

obj_dir/Vtb_memmap_template: $(Z486_DIR)/z486_cache_map_pkg.sv $(Z486_DIR)/z486_pc98_preset.svh $(TB_MEMMAP_SRCS) $(CPP_MEMMAP_SRCS)
	@echo "Building memory-map template unit test with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --top-module tb_memmap_template \
		$(Z486_DIR)/z486_cache_map_pkg.sv $(TB_MEMMAP_SRCS) $(CPP_MEMMAP_SRCS)
	@echo "Build complete: obj_dir/Vtb_memmap_template"

obj_dir/Vtb_interrupt_nmi: $(Z486_DIR)/z486_pkg.sv $(Z486_DIR)/interrupt_controller.sv $(TB_INTERRUPT_NMI_SRCS)
	@echo "Building interrupt-controller NMI bench with Verilator..."
	$(VERILATOR) --timing -Wall -Wno-fatal -Wno-UNOPTFLAT -Wno-SYNCASYNCNET \
		--binary -O3 -j $(JOBS) -I$(Z486_DIR) \
		-CFLAGS "-std=c++14 -O3" --top-module tb_interrupt_nmi \
		$(Z486_DIR)/z486_pkg.sv $(Z486_DIR)/interrupt_controller.sv \
		$(TB_INTERRUPT_NMI_SRCS)
	@echo "Build complete: obj_dir/Vtb_interrupt_nmi"

obj_dir/Vtb_paging_walker: $(Z486_DIR)/z486_pkg.sv $(Z486_DIR)/paging_walker.sv $(TB_PAGING_WALKER_SRCS)
	@echo "Building page-walker A/D write-back bench with Verilator..."
	$(VERILATOR) --timing -Wall -Wno-fatal -Wno-UNOPTFLAT -Wno-SYNCASYNCNET \
		--binary -O3 -j $(JOBS) -I$(Z486_DIR) \
		-CFLAGS "-std=c++14 -O3" --top-module tb_paging_walker \
		$(Z486_DIR)/z486_pkg.sv $(Z486_DIR)/paging_walker.sv \
		$(TB_PAGING_WALKER_SRCS)
	@echo "Build complete: obj_dir/Vtb_paging_walker"

obj_dir/Vtb_cache_flush: $(RTL_SRCS) $(RTL_DEPS) $(TB_CACHE_FLUSH_SRCS)
	@echo "Building cache-flush controller bench with Verilator..."
	$(VERILATOR) --timing -Wall -Wno-fatal -Wno-UNOPTFLAT -Wno-SYNCASYNCNET \
		--binary -O3 -j $(JOBS) -I$(Z486_DIR) -I$(X87_DIR) -I$(X87_REF_DIR) \
		-CFLAGS "-std=c++14 -O3" --top-module tb_cache_flush \
		$(RTL_SRCS) $(TB_CACHE_FLUSH_SRCS)
	@echo "Build complete: obj_dir/Vtb_cache_flush"

obj_dir/Vtb_x87_bridge: $(X87_DIR)/x87_bridge.sv $(TB_X87_BRIDGE_SRCS) $(CPP_X87_BRIDGE_SRCS)
	@echo "Building x87 bridge unit test with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --top-module tb_x87_bridge $(TB_X87_BRIDGE_SRCS) $(X87_DIR)/x87_bridge.sv $(CPP_X87_BRIDGE_SRCS)
	@echo "Build complete: obj_dir/Vtb_x87_bridge"

$(X87_UCODE_GEN): $(X87_DIR)/build_x87_microcode.py
	cd $(X87_DIR) && ./build_x87_microcode.py

$(X87_COMMAND_GEN): $(X87_DIR)/build_x87_command_decode.py
	cd $(X87_DIR) && ./build_x87_command_decode.py

$(X87_LOGEXP_GEN): $(X87_DIR)/build_x87_logexp_tables.py
	cd $(X87_DIR) && ./build_x87_logexp_tables.py

obj_dir/Vtb_x87_sequencer: $(X87_DIR)/x87_ucode.svh $(X87_DIR)/x87_entries.svh \
		$(X87_DIR)/x87_ucode_pkg.sv $(X87_DIR)/x87_ucode_rom.sv \
		$(X87_DIR)/x87_sequencer.sv $(TB_X87_SEQ_SRCS) $(CPP_X87_SEQ_SRCS)
	@echo "Building x87 sequencer unit test with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --top-module tb_x87_sequencer \
		$(X87_DIR)/x87_ucode_pkg.sv $(TB_X87_SEQ_SRCS) \
		$(X87_DIR)/x87_ucode_rom.sv $(X87_DIR)/x87_sequencer.sv \
		$(CPP_X87_SEQ_SRCS)
	@echo "Build complete: obj_dir/Vtb_x87_sequencer"

obj_dir/Vtb_x87_executor: $(X87_DIR)/x87_ucode.svh $(X87_DIR)/x87_entries.svh \
		$(X87_DIR)/x87_pkg.sv $(X87_REF_DIR)/x87_roundint.sv \
		$(X87_REF_DIR)/x87_addsub.sv $(X87_REF_DIR)/x87_mul.sv \
		$(X87_REF_DIR)/x87_divsqrt.sv $(X87_DIR)/x87_cordic_rom.sv \
		$(X87_REF_DIR)/x87_cordic_atan_q80.svh \
		$(X87_REF_DIR)/x87_trans.sv \
		$(X87_DIR)/x87_ucode_pkg.sv $(X87_DIR)/x87_ucode_rom.sv \
		$(X87_DIR)/x87_sequencer.sv $(X87_DIR)/x87_executor.sv \
		$(X87_DIR)/x87_cordic_scratch.sv \
		$(TB_X87_EXECUTOR_SRCS) $(CPP_X87_EXECUTOR_SRCS)
	@echo "Building x87 executor unit test with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --top-module tb_x87_executor \
		$(X87_DIR)/x87_pkg.sv $(X87_DIR)/x87_ucode_pkg.sv \
		$(TB_X87_EXECUTOR_SRCS) $(X87_REF_DIR)/x87_roundint.sv \
		$(X87_REF_DIR)/x87_addsub.sv $(X87_REF_DIR)/x87_mul.sv \
		$(X87_REF_DIR)/x87_divsqrt.sv $(X87_DIR)/x87_cordic_rom.sv \
		$(X87_DIR)/x87_cordic_scratch.sv \
		$(X87_REF_DIR)/x87_trans.sv \
		$(X87_DIR)/x87_ucode_rom.sv $(X87_DIR)/x87_sequencer.sv \
		$(X87_DIR)/x87_executor.sv $(CPP_X87_EXECUTOR_SRCS)
	@echo "Build complete: obj_dir/Vtb_x87_executor"

obj_dir_x87_testfloat/Vtb_x87_testfloat: \
		$(X87_DIR)/x87_ucode.svh $(X87_DIR)/x87_entries.svh \
		$(X87_DIR)/x87_pkg.sv $(X87_DIR)/x87_cordic_rom.sv \
		$(X87_DIR)/x87_cordic_scratch.sv \
		$(X87_DIR)/x87_ucode_pkg.sv $(X87_DIR)/x87_ucode_rom.sv \
		$(X87_DIR)/x87_sequencer.sv $(X87_DIR)/x87_executor.sv \
		$(TB_X87_TESTFLOAT_SRCS) $(CPP_X87_TESTFLOAT_SRCS)
	@echo "Building x87 TestFloat testbench with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --Mdir obj_dir_x87_testfloat \
		--top-module tb_x87_testfloat \
		$(X87_DIR)/x87_pkg.sv $(X87_DIR)/x87_ucode_pkg.sv \
		$(TB_X87_TESTFLOAT_SRCS) $(X87_DIR)/x87_cordic_rom.sv \
		$(X87_DIR)/x87_cordic_scratch.sv \
		$(X87_DIR)/x87_ucode_rom.sv $(X87_DIR)/x87_sequencer.sv \
		$(X87_DIR)/x87_executor.sv $(CPP_X87_TESTFLOAT_SRCS)
	@echo "Build complete: obj_dir_x87_testfloat/Vtb_x87_testfloat"

obj_dir_x87_core/Vtb_x87_core: $(X87_DIR)/x87_ucode.svh \
		$(X87_DIR)/x87_entries.svh $(X87_DIR)/x87_pkg.sv \
		$(X87_DIR)/x87_cordic_rom.sv \
		$(X87_DIR)/x87_cordic_scratch.sv $(X87_DIR)/x87_ucode_pkg.sv \
		$(X87_DIR)/x87_ucode_rom.sv $(X87_DIR)/x87_sequencer.sv \
		$(X87_DIR)/x87_executor.sv \
		$(X87_DIR)/x87_transfer_fifo.sv \
		$(X87_DIR)/x87_stack_mem.sv \
		$(X87_DIR)/x87_command_rom.sv \
		$(X87_DIR)/x87_logexp_rom.sv \
		$(X87_DIR)/x87_control.sv $(TB_X87_CORE_SRCS) \
		$(CPP_X87_CORE_SRCS)
	@echo "Building x87 core unit test with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --Mdir obj_dir_x87_core \
		--top-module tb_x87_core $(TB_X87_CORE_SRCS) \
		$(X87_DIR)/x87_pkg.sv $(X87_DIR)/x87_cordic_rom.sv \
		$(X87_DIR)/x87_cordic_scratch.sv \
		$(X87_DIR)/x87_ucode_pkg.sv $(X87_DIR)/x87_ucode_rom.sv \
		$(X87_DIR)/x87_sequencer.sv $(X87_DIR)/x87_executor.sv \
		$(X87_DIR)/x87_transfer_fifo.sv \
		$(X87_DIR)/x87_stack_mem.sv $(X87_DIR)/x87_command_rom.sv \
		$(X87_DIR)/x87_control.sv \
		$(CPP_X87_CORE_SRCS)
	@echo "Build complete: obj_dir_x87_core/Vtb_x87_core"

obj_dir_x87_fifo/Vtb_x87_transfer_fifo: \
		$(X87_DIR)/x87_transfer_fifo.sv $(TB_X87_FIFO_SRCS) \
		$(CPP_X87_FIFO_SRCS)
	@echo "Building x87 transfer FIFO unit test with Verilator..."
	$(VERILATOR) $(VFLAGS_NOTRACE) --Mdir obj_dir_x87_fifo \
		--top-module tb_x87_transfer_fifo $(TB_X87_FIFO_SRCS) \
		$(X87_DIR)/x87_transfer_fifo.sv $(CPP_X87_FIFO_SRCS)
	@echo "Build complete: obj_dir_x87_fifo/Vtb_x87_transfer_fifo"

test: test-simple

# Run tests
test-simple: build
	@echo "Running z486 simple instruction tests..."
	./test_simple.py

test-full: build
	@echo "Running external single-step reference tests (prepare.sh installs datasets)..."
	./test_singlestep_real.py --limit 0 --no-color
	./test_singlestep_protected.py -n 0 -nt

test-protected: obj_dir/Vtb_protected_mode
	@echo "Running protected mode tests..."
	./test_protected_mode.py

test-386: obj_dir/Vtb_test386
	@echo "Running test386.asm..."
	./test386.py

test-l1-cache: obj_dir/Vtb_l1_cache
	@echo "Running L1 cache unit test..."
	./obj_dir/Vtb_l1_cache

test-l1-icache: obj_dir/Vtb_l1_icache
	@echo "Running L1 instruction cache unit test..."
	./obj_dir/Vtb_l1_icache

obj_dir/Vtb_data_access: $(Z486_DIR)/z486_pkg.sv $(Z486_DIR)/data_access.sv $(RTL_DEPS) tb_data_access.sv
	$(VERILATOR) --binary --timing -Wno-fatal -j $(JOBS) -I$(Z486_DIR) --top-module tb_data_access \
		$(Z486_DIR)/z486_pkg.sv $(Z486_DIR)/data_access.sv tb_data_access.sv

test-data-access: obj_dir/Vtb_data_access
	./obj_dir/Vtb_data_access

test-memory-order: obj_dir/Vtb_memory_order
	@echo "Running device/store ordering unit test..."
	./obj_dir/Vtb_memory_order

# A younger direct load's write-back must win the GPR bytes it writes against
# an older hardwired load's deferred MEM token retiring in the same cycle.
test-load-waw: obj_dir/Vtb_load_waw
	@echo "Running same-cycle load write-arbitration unit test..."
	@./obj_dir/Vtb_load_waw | tee obj_dir/z486_load_waw.out | grep -q "LOAD WAW TEST PASS" \
		|| (echo "load write-arbitration test FAIL"; exit 1)

# Static checks revived from the fork: they guard the microcode/PLA images and
# the synthesis pragmas, none of which any RTL bench covers.
check-pragmas:
	@echo "Checking synthesis translate_off/translate_on balance..."
	@./check_pragmas.py $(Z486_DIR)

check-rom-columns:
	@echo "Scanning ROM images for constant (foldable) bit columns..."
	@./check_rom_columns.py $(Z486_DIR)

check-shift-ucode:
	@echo "Scanning ucode.hex for unrecognized SHIFT source pairings..."
	@./check_shift_ucode.py $(Z486_DIR)/ucode.hex

# The survey's old findings were fixed; a new finding must fail the gate.
test-gpr-hazard: obj_dir/Vtb_gpr_hazard
	@./obj_dir/Vtb_gpr_hazard | tee obj_dir/z486_gpr_hazard.out
	@grep -q 'GPR HAZARD SURVEY: no hazards observed' obj_dir/z486_gpr_hazard.out

# The shared producer arbitration: one order for the commit and all views.
test-gpr-merge: obj_dir/Vtb_gpr_write_merge
	@echo "Running GPR write-merge unit bench..."
	@./obj_dir/Vtb_gpr_write_merge | tee obj_dir/z486_gpr_merge.out | grep -q "GPR WRITE MERGE TEST PASS" \
		|| (echo "GPR write-merge test FAIL"; exit 1)

test-memmap-template: obj_dir/Vtb_memmap_template
	@echo "Running memory-map template unit test..."
	./obj_dir/Vtb_memmap_template

# Proves the NMI deferred-delivery rule: an edge in the accept-to-SETNMI window
# is latched but not re-dispatched nested; CLRNMI (the IRET unmask) releases it.
test-interrupt-nmi: obj_dir/Vtb_interrupt_nmi
	@echo "Running interrupt-controller NMI deferred-delivery bench..."
	@./obj_dir/Vtb_interrupt_nmi | tee obj_dir/z486_interrupt_nmi.out \
		| grep -q "TB_INTERRUPT_NMI: PASS" \
		|| (echo "interrupt NMI bench FAIL"; exit 1)

test-paging-walker: obj_dir/Vtb_paging_walker
	@echo "Running page-walker A/D write-back bench..."
	@./obj_dir/Vtb_paging_walker | tee obj_dir/z486_paging_walker.out \
		| grep -q "PAGING WALKER TEST PASS" \
		|| (echo "page-walker A/D write-back bench FAIL"; exit 1)

test-cache-flush: obj_dir/Vtb_cache_flush
	@echo "Running whole-L1 flush controller bench..."
	@./obj_dir/Vtb_cache_flush | tee obj_dir/z486_cache_flush.out \
		| grep -q "TB_CACHE_FLUSH: PASS" \
		|| (echo "cache-flush controller bench FAIL"; exit 1)

test-x87-bridge: obj_dir/Vtb_x87_bridge
	@echo "Running x87 bridge unit test..."
	./obj_dir/Vtb_x87_bridge

test-x87-sequencer: obj_dir/Vtb_x87_sequencer
	@echo "Running x87 sequencer unit test..."
	./obj_dir/Vtb_x87_sequencer

test-x87-executor: obj_dir/Vtb_x87_executor
	@echo "Running x87 executor unit test..."
	./obj_dir/Vtb_x87_executor

TESTFLOAT_GEN ?= $(CURDIR)/../../qemu/subprojects/berkeley-testfloat-3/build/Linux-x86_64-GCC/testfloat_gen
X87_TESTFLOAT_CASES ?= 512

test-x87-testfloat: obj_dir_x87_testfloat/Vtb_x87_testfloat
	@echo "Running x87 arithmetic against Berkeley TestFloat..."
	./run_x87_testfloat.sh "$(TESTFLOAT_GEN)" \
		./obj_dir_x87_testfloat/Vtb_x87_testfloat \
		"$(X87_TESTFLOAT_CASES)"

test-x87-fifo: obj_dir_x87_fifo/Vtb_x87_transfer_fifo
	@echo "Running x87 transfer FIFO unit test..."
	./obj_dir_x87_fifo/Vtb_x87_transfer_fifo

test-x87-core: obj_dir_x87_core/Vtb_x87_core
	@echo "Running x87 core unit test..."
	./obj_dir_x87_core/Vtb_x87_core

test-x87-integration: obj_dir_x87/Vtb_protected_mode
	@echo "Running x87-enabled CPU protocol tests..."
	Z486_ENABLE_X87=1 Z486_TESTBENCH=$(CURDIR)/obj_dir_x87/Vtb_protected_mode ./test_protected_mode.py x87_protocol x87_env32 x87_arithmetic x87_m32_page_fault x87_heap32 x87_qemu_special x87_qemu_exceptions x87_off_sx

test-x87-integer: obj_dir_x87_int/Vtb_z486
	@echo "Running integer regressions with x87 enabled..."
	Z486_TESTBENCH=$(CURDIR)/obj_dir_x87_int/Vtb_z486 ./test_simple.py --no-color
	Z486_TESTBENCH=$(CURDIR)/obj_dir_x87_int/Vtb_z486 ./test_singlestep_real.py --no-color
	Z486_TESTBENCH=$(CURDIR)/obj_dir_x87_int/Vtb_z486 ./test_singlestep_protected.py -nt

dhrystone:
	$(MAKE) -C dhrystone compare

# Clean build artifacts
clean:
	rm -rf obj_dir_x87_testfloat
	rm -rf obj_dir_x87_fifo
	rm -rf obj_dir_x87_core
	rm -rf obj_dir_x87
	rm -rf obj_dir_x87_int
	rm -rf obj_dir
	rm -f trace.fst trace.vcd
	rm -f result.txt
	rm -f *.hex

# Help
help:
	@echo "z486 Test Makefile"
	@echo "=================="
	@echo ""
	@echo "Targets:"
	@echo "  make build          - Build all testbenches with Verilator"
	@echo "  make test-simple    - Run default test suite (~13 test files)"
	@echo "  make test-386       - Run test386.asm"
	@echo "  make test-l1-cache  - Run PIPT L1 cache unit test"
	@echo "  make test-l1-icache - Run PIPT L1 instruction cache unit test"
	@echo "  make test-memory-order - Run device/store ordering unit test"
	@echo "  make test-load-waw  - Run same-cycle GPR write-arbitration unit test"
	@echo "  make test-gpr-hazard - Gate the GPR hazard survey"
	@echo "  make test-memmap-template - Run memory-map template unit test"
	@echo "  make test-interrupt-nmi - Run interrupt-controller NMI deferred-delivery bench"
	@echo "  make test-x87-bridge - Run x87 protocol bridge unit test"
	@echo "  make test-x87-core - Run x87 state and transfer unit test"
	@echo "  make test-x87-testfloat - Check arithmetic with Berkeley TestFloat"
	@echo "  make test-x87-integration - Run x87-enabled CPU protocol test"
	@echo "  make dhrystone      - Compare released z386 and current z486 on Dhrystone"
	@echo "  make clean          - Remove build artifacts"
	@echo "  make help           - Show this help message"
