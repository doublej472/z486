VIVADO ?= $(HOME)/Xilinx/Vivado/2024.2/bin/vivado
BOOTGEN ?= $(HOME)/Xilinx/Vivado/2024.2/bin/bootgen
DTC ?= dtc
CPU_MHZ ?= 100

VIVADO_BINDIR := $(dir $(VIVADO))
XVLOG ?= $(VIVADO_BINDIR)xvlog
XELAB ?= $(VIVADO_BINDIR)xelab
XSIM ?= $(VIVADO_BINDIR)xsim

BUILD := build
BIT_DIR := $(BUILD)/z486_kv260.runs/impl_1
BIT := $(BIT_DIR)/kv260_top.bit
BIT_BIN := $(BIT_DIR)/kv260_top.bit.bin
APP := $(BUILD)/app/z486-led
CPU_DIR := ../..
CPU_DIR_ABS := $(abspath $(CPU_DIR))
SIM_DIR := $(BUILD)/xsim
SIM_TOP := tb_z486_led_demo
SIM_RTL := $(shell sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$$/d' \
	../common/rtl_sources.f)
SIM_SOURCES := $(addprefix $(CPU_DIR_ABS)/,$(SIM_RTL))

.PHONY: all firmware sim sim-prepare package package-files overlay \
	cpu cpu-x87 clean

all: firmware
	$(VIVADO) -mode batch -source scripts/build.tcl

sim: sim-prepare
	cd $(SIM_DIR) && $(XVLOG) --sv --relax -d Z486_XILINX=1 \
		-d Z486_SIM_ENABLE_X87=1 \
		-i $(CPU_DIR_ABS) -i $(CPU_DIR_ABS)/x87 \
		$(SIM_SOURCES) \
		$(CPU_DIR_ABS)/boards/common/sim/$(SIM_TOP).sv
	cd $(SIM_DIR) && $(XELAB) --relax --mt auto --timescale 1ns/1ps \
		-s $(SIM_TOP)_snapshot work.$(SIM_TOP)
	rm -f $(SIM_DIR)/xsim.log
	cd $(SIM_DIR) && $(XSIM) $(SIM_TOP)_snapshot --runall --onerror quit \
		--log xsim.log
	grep -F "PASS: x86 firmware generated the LED pattern" \
		$(SIM_DIR)/xsim.log

sim-prepare:
	mkdir -p $(SIM_DIR)/boards/firmware
	nasm -D BLINK_DELAY=1 -f bin \
		-o $(SIM_DIR)/boards/firmware/blink.bin ../firmware/blink.asm
	test "$$(stat -c '%s' $(SIM_DIR)/boards/firmware/blink.bin)" = 65536
	od -An -v -t x4 $(SIM_DIR)/boards/firmware/blink.bin | \
		tr -s ' ' '\n' | sed '/^$$/d' > $(SIM_DIR)/boards/firmware/blink.hex
	test "$$(wc -l < $(SIM_DIR)/boards/firmware/blink.hex)" = 16384
	cp $(CPU_DIR)/ucode.hex $(CPU_DIR)/pla_entry_rom.hex \
		$(CPU_DIR)/pla_group_entry.hex $(CPU_DIR)/x87/x87_ucode.mem \
		$(SIM_DIR)/

package: all
	$(MAKE) package-files

package-files: $(APP)/z486_led.bit.bin $(APP)/z486_led.dtbo \
	$(APP)/shell.json

overlay: $(BUILD)/z486_led.dtbo

$(BIT_BIN): $(BIT)
	printf 'all:\n{\n  %s\n}\n' 'kv260_top.bit' > $(BIT_DIR)/kv260_top.bif
	cd $(BIT_DIR) && $(BOOTGEN) -arch zynqmp -image kv260_top.bif \
		-w -process_bitstream bin

$(BUILD)/z486_led.dtbo: overlay/z486_led.dtso
	mkdir -p $(BUILD)
	$(DTC) -@ -I dts -O dtb -o $@ $<

$(APP)/z486_led.bit.bin: $(BIT_BIN)
	mkdir -p $(APP)
	cp $< $@

$(APP)/z486_led.dtbo: $(BUILD)/z486_led.dtbo
	mkdir -p $(APP)
	cp $< $@

$(APP)/shell.json: package/shell.json
	mkdir -p $(APP)
	cp $< $@

firmware:
	$(MAKE) -C ../firmware

cpu:
	$(VIVADO) -mode batch -source scripts/build_cpu.tcl \
		-tclargs 0 $(CPU_MHZ)

cpu-x87:
	$(VIVADO) -mode batch -source scripts/build_cpu.tcl \
		-tclargs 1 $(CPU_MHZ)

clean:
	rm -rf build build-x87 build-cpu build-cpu-x87
