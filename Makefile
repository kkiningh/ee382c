# First target is default
.PHONY: all
all: synth_all

# Use /tmp/ for builds since otherwise we can run into AFS errors :(
BUILD = /tmp/$(shell whoami)/ee382c

# Search path for source files
SEARCH_PATH  = ./src/				# Top level modules
SEARCH_PATH += ./src/clib			# CLib code
SEARCH_PATH	+= ./src/router			# Router code

### Simulation
SIMV_LIBS	 = ./tests/common		# Code common to all testbenches (needs to be first)
SIMV_LIBS	+= $(SEARCH_PATH) 		# All other code (besides external IP)
SIMV_LIBS	+= $$SYNOPSYS/dw/sim_ver	# Synopsys Designware verilog files

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
VCS_OPTIONS += -timescale=1ns/1ps   # Use 1ns timescale
VCS_OPTIONS += -Mupdate             # Use incremental compilation (on by default)
VCS_OPTIONS += +rad					# Enable Radiant Tech optimization
VCS_OPTIONS += +vcs+lic+wait        # Wait to checkout a license if none avalible
#VCS_OPTIONS += +vcs+vcdpluson		# Enables signal dumping for the entire design
#VCS_OPTIONS += +memcbk             # Allow multidimensional arrays to be dumped
									# during runtime. Requires the use of the
									# +vcs+dumparrays runtime option

# Add the library folders to the search path
VCS_INCLUDE += $(patsubst %,-y %,$(SIMV_LIBS))
VCS_INCLUDE += $(patsubst %, +incdir+%, $(SIMV_LIBS))

.PHONY: sim_all
sim_all: $(BUILD)/mesh4x4/rate_12.saif.gz
sim_all: $(BUILD)/mesh4x4/rate_25.saif.gz
sim_all: $(BUILD)/mesh4x4/rate_37.saif.gz
sim_all: $(BUILD)/mesh4x4/rate_50.saif.gz

sim_all: $(BUILD)/torus4x4/rate_12.saif.gz
sim_all: $(BUILD)/torus4x4/rate_25.saif.gz
sim_all: $(BUILD)/torus4x4/rate_37.saif.gz
sim_all: $(BUILD)/torus4x4/rate_50.saif.gz

sim_all: $(BUILD)/fbfly4x4/rate_12.saif.gz
sim_all: $(BUILD)/fbfly4x4/rate_25.saif.gz
sim_all: $(BUILD)/fbfly4x4/rate_38.saif.gz
sim_all: $(BUILD)/fbfly4x4/rate_50.saif.gz

# Include the dependency information.
include ./tests/Overrides.mk

$(BUILD)/%.simv: tests/%.v
	@mkdir -p $(@D)
	$(strip $(VCS)) -o $@ -l /dev/null -Mdir=$@-csrc \
		$(strip $(VCS_OPTIONS)) \
		$(strip $(VCS_INCLUDE)) \
		$^ \
		> $@-vcs.log

%.vcd: %.simv
	$^ -q -vcd $@ -k $(@D)/ucli.key \
		> $^.log

%.vcd.gz: %.vcd
	gzip $^

%.saif.gz: %.vcd
	vcd2saif -64 -input $^ -output $@

### Synthesis
DCS          = dc_shell-xg-t -64bit # Always use 64-bit DCS
DCS_OPTIONS  = -topographical       # Use topograpical mode
DCS_SCRIPT   = ./tcl/syn-router.tcl # Sythesis script

.PHONY: synth_all
synth_all: $(BUILD)/data/mesh4x4.synthesis.ddc
#synth_all: $(BUILD)/data/torus4x4.synthesis.ddc
#synth_all: $(BUILD)/data/fbfly4x4.synthesis.ddc

$(BUILD)/data/%.synthesis.ddc $(BUILD)/data/%.synthesis.v: src/%.v $(DCS_SCRIPT)
	@mkdir -p $(BUILD)
	@mkdir -p $(BUILD)/data
	@mkdir -p $(BUILD)/reports
	@mkdir -p $(BUILD)/reports/synthesis
	$(DCS) $(DCS_OPTIONS) \
		-x "set BUILD_DIR $(BUILD); set TOP $*; set SEARCH_PATH [list $(strip $(SEARCH_PATH))];" \
		-f $(DCS_SCRIPT)

.PHONY: clean
clean:
	-rm -rf $(BUILD_DIR)
