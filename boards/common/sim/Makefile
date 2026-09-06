CPU_DIR := ../../..
OBJ_DIR := boards/common/sim/build/obj_dir
TOP := tb_z486_led_demo

VERILATOR ?= verilator
VFLAGS := --binary --timing -Wall -Wno-fatal -Wno-UNOPTFLAT
VFLAGS += -Wno-SYNCASYNCNET -Wno-PINCONNECTEMPTY -Wno-DECLFILENAME
VFLAGS += -Wno-TIMESCALEMOD
VFLAGS += -I. -Ix87 -f boards/common/rtl_sources.f

.PHONY: all firmware build run clean

all: run

firmware:
	$(MAKE) -C ../../firmware

build: firmware
	mkdir -p build/obj_dir
	cd $(CPU_DIR) && $(VERILATOR) $(VFLAGS) --Mdir $(OBJ_DIR) \
		--top-module $(TOP) boards/common/sim/$(TOP).sv

run: build
	cd $(CPU_DIR) && $(OBJ_DIR)/V$(TOP)

clean:
	rm -rf build
