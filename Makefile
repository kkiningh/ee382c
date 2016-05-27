BUILD_DIR = ./build

# First target is default
.PHONY: all
all: $(BUILD_DIR)/simv.vcd

### Simulation
SIMV		= $(BUILD_DIR)/simv
SIMV_BUILD	= $(BUILD_DIR)/simv-build
SIMV_TEST	= mesh_3x3
SIMV_TOP	= verif/$(SIMV_TEST)/testbench.v
SIMV_LIBS	= ./verif/$(SIMV_TEST) \
			  ./src/clib \
			  ./src/router \
			  $$SYNOPSYS/dw/sim_ver

VCS          = vcs -full64			# Always use 64-bit VCS
VCS_OPTIONS += -debug_pp			# Enable the use of DVE
VCS_OPTIONS += -PP -line			# Enable VCD dumps with line numbers
									# Note: requires use of $vcdpluson and 
									# $dumpvars commands in testbench
VCS_OPTIONS += -notice				# Turn on verbose diagnostics...
VCS_OPTIONS += -q					# ...but be quite about everything else
VCS_OPTIONS += +lint=all,noVCDE 	# Turn on verilog warnings 
VCS_OPTIONS += +v2k					# Use the Verilog-2001 language
VCS_OPTIONS += +libext+.v			# Library files use the ".v" extension
VCS_OPTIONS += -timescale=1ns/1ns   # Use 1ns timescale
VCS_OPTIONS += -Mupdate             # Use incremental compilation (on by default)
VCS_OPTIONS += +rad					# Enable Radiant Tech optimization (?)
VCS_OPTIONS += +vcs+lic+wait        # Wait to checkout a license if none avalible
VCS_OPTIONS += +memcbk              # Allow multidimensional arrays to be dumped
									# during runtime. Requires the use of the
									# +vcs+dumparrays runtime option

# Add the library folders to the search path
VCS_INCLUDE += $(patsubst %,-y %,$(SIMV_LIBS))
VCS_INCLUDE += $(patsubst %, +incdir+%, $(SIMV_LIBS))

$(SIMV): $(SIMV_TOP)
	@mkdir -p $(SIMV_BUILD)
	$(strip $(VCS)) -o $@ -l $(SIMV_BUILD)/vcs.log -Mdir=$(SIMV_BUILD)/csrc \
		$(strip $(VCS_OPTIONS)) \
		$(SIMV_TOP) $(strip $(VCS_INCLUDE))

$(BUILD_DIR)/simv.vcd: $(SIMV)
	$(SIMV) -q +vpdfile+$@ -k $(SIMV_BUILD)/ucli.key # +vcs+dumparrays +vcs+dumpvars

### Synthesis
DCS_TOP      = router_wrap
DCS_BUILD    = $(BUILD_DIR)
DCS_SCRIPT   = ./tcl/syn-router.tcl

DCS          = dc_shell-xg-t -64bit # Always use 64-bit DCS
DCS_OPTIONS += -topographical       # Use topograpical mode

.PHONY: synth
synth: $(DCS_BUILD)/data/$(DCS_TOP).synthesis.v

$(DCS_BUILD)/data/$(DCS_TOP).synthesis.v: $(DCS_SCRIPT)
	@mkdir -p $(DCS_BUILD)
	@mkdir -p $(DCS_BUILD)/data
	@mkdir -p $(DCS_BUILD)/reports
	@mkdir -p $(DCS_BUILD)/reports/synthesis
	$(DCS) $(DCS_OPTIONS) -x "set BUILD_DIR $(DCS_BUILD)" -f $(DCS_SCRIPT)

.PHONY: clean
clean:
	-rm -rf $(BUILD_DIR)
