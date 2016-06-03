# Use multiple cores
set_host_options -max_cores 16

# Setup the technology libraries, Milkyway database, tech map, etc
source ./tcl/common-setup.tcl

# ------------------------------------------------------------------------------
# Setup for Formality verification
# ------------------------------------------------------------------------------

set_svf ${BUILD_DIR}/data/${TOP}.synthesis.svf

# ------------------------------------------------------------------------------
# Setup for SAIF name mapping database
# ------------------------------------------------------------------------------

saif_map -start

################################################################################
# Design Elaboration (pre-synthsys setup)
################################################################################

# ------------------------------------------------------------------------------
# Project source setup
# ------------------------------------------------------------------------------

# The search path specifies where dc_shell will look for referenced designs 
# as well as include files.
set_app_var search_path [concat $search_path ${SEARCH_PATH}]

# The set of directories that contain verilog source files. Can also contain
# individual source files in seperate directories
set src_directories [list ${SEARCH_PATH}]

# The set of verilog files that should not be considered for analysis. This 
# should only be inlcude files or files that don't actually contain verilog.
# NOTE: if you enable this add -exclude $src_exclude to the analyze call below!
#set src_exclude { }

# Default to read Verilog as standard version 2001 (not 2005)
set_app_var hdlin_vrlg_std 2001

# Don't optimize constants for Formality and ID registers.
set_app_var compile_seqmap_propagate_constants false

# Identify architecturally instantiated clock gates
# Note: This application variable must be set BEFORE the RTL is read in.
set_app_var power_cg_auto_identify true

# Check for latches in RTL
set_app_var hdlin_check_no_latch true

# Set the library working directory
define_design_lib work -path ${BUILD_DIR}/work

# ------------------------------------------------------------------------------
# Design analsis and elaboration
# ------------------------------------------------------------------------------

# Analyze reads in the specified verilog source files and creates a technology
# independent representation in memory. Any verilog errors (should) get
# reported here
analyze $src_directories -autoread -top $TOP -format verilog

# Elabortate the design.
elaborate -architecture verilog $TOP

# Link the design 
current_design $TOP
link

#check_design -no_warnings

################################################################################
# Synthesis
################################################################################

# ------------------------------------------------------------------------------
# Clock and constraints
# ------------------------------------------------------------------------------

set common_clock_ports [list clk]

# Declares the clocks present in the design with period, uncertainty and
# latency information for synthesis:
#
#   Period      - Describes the frequency to be acheieved by synthesis.
#
#   Uncertainty - Describes all parameters that could influence the difference
#                 in clock timing between two related flops. Since jitter is
#                 explicitly mentioned this will include OCV, skew and margin.
#
#   Latency     - Describes the delay in the clock tree from the core clock pin
#                 to the flop clock pin; at this point it is an estimate.
#
foreach clock_name ${common_clock_ports} {
  create_clock -name ${clock_name} \
    -period [expr ${clock_period} - ${clock_period_jitter}] \
    [get_ports ${clock_name}]

  set_clock_uncertainty \
    -setup [expr ${setup_margin} + $pre_cts_clock_skew_estimate] \
    [get_clocks ${clock_name} ]

  set_clock_uncertainty \
    -hold [expr ${hold_margin} + $pre_cts_clock_skew_estimate] \
    [get_clocks ${clock_name}]

  set_clock_latency -source -fall -early [expr 0.0 - $clock_dutycycle_jitter] \
    [get_clocks ${clock_name} ]

  set_clock_latency -source -fall -late  [expr 0.0 + $clock_dutycycle_jitter] \
    [get_clocks ${clock_name} ]

  set_clock_latency $pre_cts_clock_latency_estimate \
    [get_clocks ${clock_name}]

  echo "Defined clock $clock_name"
}

# ------------------------------------------------------------------------------
# Virtual clocks
# ------------------------------------------------------------------------------

create_clock -name VCLK -period [expr ${clock_period} - ${clock_period_jitter}]
set_clock_uncertainty -setup [expr ${setup_margin} + $pre_cts_clock_skew_estimate] [get_clocks {VCLK} ]
set_clock_uncertainty -hold  [expr ${hold_margin} + $pre_cts_clock_skew_estimate] [get_clocks {VCLK} ]
set_clock_latency -source -fall -early [expr 0.0 - $clock_dutycycle_jitter] [get_clocks {VCLK}]
set_clock_latency -source -fall -late  [expr 0.0 + $clock_dutycycle_jitter] [get_clocks {VCLK}]
set_clock_latency $pre_cts_clock_latency_estimate [get_clocks {VCLK} ]

echo "Defined clock VCLK"

# ------------------------------------------------------------------------------
# Set design context
# ------------------------------------------------------------------------------

# Set the maximum fanout value on the design
set_max_fanout ${max_fanout} $TOP

# Set the maximum transition value on the design
set_max_transition $max_transition($slow_corner_pvt) $TOP

# Load all outputs with suitable capacitance
set_load $output_load [all_outputs]

# Derive list of clock ports
set clock_ports [filter_collection [get_attribute [get_clocks] sources] object_class==port]

# Drive input ports with a standard driving cell and input transition
set_driving_cell -library $target_library_name($slow_corner_pvt) \
                 -from_pin ${driving_from_pin} \
                 -input_transition_rise $max_transition($slow_corner_pvt) \
                 -input_transition_fall $max_transition($slow_corner_pvt) \
                 -lib_cell ${driving_cell} \
                 -pin ${driving_pin} \
                 [remove_from_collection [all_inputs] ${clock_ports} ]

set_driving_cell -library $target_library_name($slow_corner_pvt) \
                 -from_pin ${clock_driving_from_pin} \
                 -input_transition_rise $max_transition($slow_corner_pvt) \
                 -input_transition_fall $max_transition($slow_corner_pvt) \
                 -lib_cell ${clock_driving_cell} \
                 -pin ${clock_driving_pin} \
                 ${clock_ports}

# ------------------------------------------------------------------------------
# Set Operating conditions (Synthesis uses best case / worst case)
# ------------------------------------------------------------------------------

set_operating_conditions \
    -max $operating_condition_name($slow_corner_pvt) \
    -max_lib [get_libs $target_library_name($slow_corner_pvt)] \
    -min $operating_condition_name($fast_corner_pvt) \
    -min_lib [get_libs $target_library_name($fast_corner_pvt)] \
    -analysis_type bc_wc

# ------------------------------------------------------------------------------
# Create default path groups
# ------------------------------------------------------------------------------

# Separating paths can help improve optimization.

set ports_clock_root [get_ports [all_fanout -flat -clock_tree -level 0]]

group_path -name Inputs  -from [remove_from_collection [all_inputs] \
                                                       $ports_clock_root]
group_path -name Outputs -to   [all_outputs]

# Group internal paths between registers
group_path -name Regs_to_Regs -from [all_registers] -to [all_registers]

# ------------------------------------------------------------------------------
# Apply power optimization constraints
# ------------------------------------------------------------------------------

# A SAIF file can be used for power optimization. Without this a default toggle
# rate of 0.1 will be used for propagating switching activity
# read_saif -auto_map_names -input ${SAIF_PATH} -instance testbench/${TOP}_inst -verbose

# Propagate the saif switching factors using static analyisis
# Note: This is depreciated and unneeded in most cases
#propagate_switching_activity -effort high

# Setting power constraints will automatically enable power prediction using
# clock tree estimation.
set_power_prediction true

# -----------------------------------------------------------------------------
# Physical constraints
# -----------------------------------------------------------------------------

# Specify ignored layers for routing to improve correlation
set_preferred_routing_direction -layers {METAL1 METAL3 METAL5} -direction horizontal
set_preferred_routing_direction -layers {METAL2 METAL4 METAL6} -direction vertical

# Target five routing layers (power on METAL6)
set_ignored_layers -min_routing_layer METAL1
set_ignored_layers -max_routing_layer METAL5

#report_ignored_layers

#report_preferred_routing_direction

# ------------------------------------------------------------------------------
# Apply synthesis tool options
# ------------------------------------------------------------------------------

set_app_var enable_recovery_removal_arcs true

# Case analysis required to support EMA value setting for memories
set_app_var case_analysis_with_logic_constants true

set_app_var physopt_enable_via_res_support true

set_app_var write_name_nets_same_as_ports true
set_app_var report_default_significant_digits 3

# ------------------------------------------------------------------------------
# Additional optimization constraints
# ------------------------------------------------------------------------------

# Control DRC/Fanout for tie cells
# This allows a fanout of 1 on tie cells to be set:
set_auto_disable_drc_nets -constant false

# Prevent assignment statements in the Verilog netlist.
set_fix_multiple_port_nets -all -buffer_constants [get_designs]

# Critical range for core
set_critical_range [expr 0.10 * ${clock_period} ] ${TOP}

# Isolate the ports for accurate timing model creation
set clock_ports [filter_collection [get_attribute [get_clocks] sources] object_class==port]
set isolated_inputs [remove_from_collection [all_inputs] $clock_ports ]

set_isolate_ports -type buffer -force [get_ports ${isolated_inputs}]
set_isolate_ports -type buffer -force [all_outputs]

# Set to enable full range of flops for synthesis consideration
set compile_filter_prune_seq_cells false

# ------------------------------------------------------------------------------
# Compile the design
# ------------------------------------------------------------------------------

compile_ultra -scan -no_autoungroup -gate_clock

# ------------------------------------------------------------------------------
# Change names before output
# ------------------------------------------------------------------------------

# If this will be a sub-block in a hierarchical design, uniquify with block
# unique names to avoid name collisions when integrating the design at the top
# level
set_app_var uniquify_naming_style ${TOP}_%s_%d
uniquify -force

define_name_rules verilog -case_insensitive
change_names -rules verilog -hierarchy -verbose > \
    ${BUILD_DIR}/reports/synthesis/${TOP}.change_names

# ------------------------------------------------------------------------------
# Write out design data
# ------------------------------------------------------------------------------

set_app_var verilogout_higher_designs_first true
set_app_var verilogout_no_tri true

write -format ddc -hierarchy -output ${BUILD_DIR}/data/${TOP}.synthesis.ddc
write -f verilog  -hierarchy -output ${BUILD_DIR}/data/${TOP}.synthesis.v

# ------------------------------------------------------------------------------
# Write out design data
# ------------------------------------------------------------------------------

# Write and close SVF file, make it available for immediate use
set_svf -off

# Write parasitics data from DCT placement for static timing analysis
write_parasitics -output ${BUILD_DIR}/data/${TOP}.synthesis.spef

# Write SDF backannotation data from DCT placement for static timing analysis
write_sdf ${BUILD_DIR}/data/${TOP}.synthesis.sdf

# Do not write out net RC info into SDC
set_app_var write_sdc_output_lumped_net_capacitance false
set_app_var write_sdc_output_net_resistance false

# Write out SDC version 1.7 to omit set_voltage for backwards compatibility
write_sdc -version 1.7 -nosplit ${BUILD_DIR}/data/${TOP}.synthesis.sdc

# If SAIF is used, write out SAIF name mapping file for PrimeTime-PX
saif_map -type ptpx -write_map ${BUILD_DIR}/reports/synthesis/${TOP}_SAIF.namemap

# ------------------------------------------------------------------------------
# Write final reports
# ------------------------------------------------------------------------------

printvar > ${BUILD_DIR}/reports/synthesis/${TOP}.vars

#check_design -multiple_designs > \
#  ${BUILD_DIR}/reports/synthesis/${TOP}.check_design

check_timing > \
  ${BUILD_DIR}/reports/synthesis/${TOP}.check_timing

report_qor > \
  ${BUILD_DIR}/reports/synthesis/${TOP}.qor

report_timing -delay max \
              -max_paths 50 \
              -nosplit \
              -cap \
              -path full_clock_expanded \
              -nets \
              -transition_time \
              -input_pins > \
  ${BUILD_DIR}/reports/synthesis/${TOP}.timing-max

# Create compacted version of the timing report showing only nets
set fr [open ${BUILD_DIR}/reports/synthesis/${TOP}.timing-max r]
set fw [open ${BUILD_DIR}/reports/synthesis/${TOP}.timing-max-nets w]

while {[gets $fr line] >= 0} {
    if {[regexp {delay} $line] ||
        [regexp { data } $line] ||
        [regexp {slack} $line] ||
        [regexp {\-\-\-\-} $line] ||
        [regexp {Group} $line] ||
        [regexp {Startpoint} $line] ||
        [regexp {Endpoint} $line] ||
        [regexp {Point} $line] ||
        [regexp { clock } $line] ||
        [regexp {(net)} $line] ||
        [regexp {^ *$} $line]
    } {
        if {![regexp {/n[0-9]+ } $line]} {
            puts $fw $line
        }
    }
}

close $fr
close $fw

#foreach SAIF_FILE ${SAIF_FILES} {
#    # Read in the SAIF file for the design
#    read_saif -auto_map_names \
#        -input $SAIF_FILE \
#        -instance testbench/${TOP}_inst
#
#    # Get the rootname of the file for reports
#    set SAIF_ROOT [file rootname [file tail ${SAIF_FILE}]]
#
#    # Report total power
#    report_power -nosplit \
#      > ${BUILD_DIR}/reports/synthesis/${TOP}.${SAIF_ROOT}.power
#
#    # Report the worst power users in the design
#    report_power -nosplit -cell -nworst 20 \
#      > ${BUILD_DIR}/reports/synthesis/${TOP}.${SAIF_ROOT}.20worst.power
#
#    # Report a detailed breakdown of all elements to the hierarchy depth given
#    report_power -nosplit -hierarchy -hier_level 2 \
#      > ${BUILD_DIR}/reports/synthesis/${TOP}.${SAIF_ROOT}.hier.power
#
#    # Reset the switching activity to the default
#    reset_switching_activity
#}

report_timing -loops > \
  ${BUILD_DIR}/reports/synthesis/${TOP}.loops

report_area -nosplit \
            -hierarchy \
            -physical > \
  ${BUILD_DIR}/reports/synthesis/${TOP}.area

#report_constraint -all_violators \
#                  -nosplit > \
#  ${BUILD_DIR}/reports/synthesis/${TOP}.constraint_violators
#
#report_design > \
#  ${BUILD_DIR}/reports/synthesis/${TOP}.design_attributes
#
#report_clocks -attributes \
#              -skew > \
#  ${BUILD_DIR}/reports/synthesis/${TOP}.clocks
#
#report_clock_gating -multi_stage \
#                    -verbose \
#                    -gated \
#                    -ungated \
#  > ${BUILD_DIR}/reports/synthesis/${TOP}.clock_gating
#
#report_clock_tree -summary \
#                  -settings \
#                  -structure > \
#  ${BUILD_DIR}/reports/synthesis/${TOP}.clock_tree
#
#query_objects -truncate 0 [all_registers -level_sensitive ] \
#  > ${BUILD_DIR}/reports/synthesis/${TOP}.latches
#
#report_isolate_ports -nosplit > \
#  ${BUILD_DIR}/reports/synthesis/${TOP}.isolate_ports
#
#report_net_fanout -threshold 32 -nosplit > \
#  ${BUILD_DIR}/reports/synthesis/${TOP}.high_fanout_nets
#
#report_port -verbose \
#            -nosplit > \
#  ${BUILD_DIR}/reports/synthesis/${TOP}.port
#
#report_hierarchy > \
#  ${BUILD_DIR}/reports/synthesis/${TOP}.hierarchy
#
#report_resources -hierarchy > \
#  ${BUILD_DIR}/reports/synthesis/${TOP}.resources
#
#report_compile_options > \
#  ${BUILD_DIR}/reports/synthesis/${TOP}.compile_options
#
report_congestion > \
  ${BUILD_DIR}/reports/synthesis/${TOP}.congestion

# Zero interconnect delay mode to investigate potential design/floorplan problems
set_zero_interconnect_delay_mode true
report_timing -delay max \
              -max_paths 50 \
              -nosplit \
              -path full_clock_expanded \
              -nets \
              -transition_time \
              -input_pins > \
  ${BUILD_DIR}/reports/synthesis/${TOP}_zero-interconnect.timing

report_qor > \
  ${BUILD_DIR}/reports/synthesis/${TOP}_zero-interconnect.qor
set_zero_interconnect_delay_mode false

quit
