QUARTUS_ROOTDIR ?= $(HOME)/altera_lite/17.0/quartus
QUARTUS_SH := $(QUARTUS_ROOTDIR)/bin/quartus_sh
PROJECT := z486_de10nano
CPU_MHZ ?= 85

.PHONY: all firmware project fmax cpu cpu-x87 clean

all: firmware project
	cd build && $(QUARTUS_SH) --flow compile $(PROJECT)

firmware:
	$(MAKE) -C ../firmware

project:
	$(QUARTUS_SH) -t scripts/build.tcl 50

fmax: firmware
	$(QUARTUS_SH) -t scripts/build.tcl 85
	cd build-fmax && $(QUARTUS_SH) --flow compile z486_de10nano_fmax

cpu:
	$(QUARTUS_SH) -t scripts/build_cpu.tcl 0 $(CPU_MHZ)
	cd build-cpu && $(QUARTUS_SH) --flow compile z486_de10nano_cpu

cpu-x87:
	$(QUARTUS_SH) -t scripts/build_cpu.tcl 1 $(CPU_MHZ)
	cd build-cpu-x87 && $(QUARTUS_SH) --flow compile z486_de10nano_cpu_x87

clean:
	rm -rf build build-fmax build-x87 build-cpu build-cpu-x87
