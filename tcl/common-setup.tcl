set sh_script_stop_severity E

################################################################################
# Technology Libraries
################################################################################

# Setup all required variables for the given technology (TSMC 180nm)
source ./tcl/tech-tsmc180fg.tcl

#-------------------------------------------------------------------------------
# Set target design libraries
#-------------------------------------------------------------------------------

# The search path is the set of directories that synopsys will search if it 
# can't find a cell definition already in memory.
# Note that $search_path is defined for us in the automatically included setup
# file $SYNOPSYS/admin/setup/.synopsys_dc.setup
set_app_var search_path [concat $search_path $stdcell_search_path]

# The synthetic library specifies what DesignWare libraries to use, if any.
# DesignWare libraries are efficent implementations of common operations like
# multiplication, addition, equality, case statements, etc, that are not tied
# to a specific technology.
# Note that these libraries must also be specified in link_library in order to
# resolve references
set_app_var synthetic_library { dw_foundation.sldb }

# The target library specifies the main library to use when compiling the
# design. It also contains default values for things like units and operating
# conditions. If multiple values are given, the first is used as the main 
# library. Note that this variable must also be specified in link_library to
# resolve references.
set_app_var target_library [concat $stdcell_library(db,$slow_corner_pvt)]

# The symbol library defines the symbols for schematic viewing of the design.
# You need this library if you intend to use the Design Vision GUI.
# We don't have a symbol library for this technology, so leave this commented
# out.
#set_app_var symbol_library { }

# The link library contains the library synopsys uses to resolve references.
# An asterisk in the value of link_library tells synopsys to look in memory
# when resolving references.
set_app_var link_library [concat * $target_library $synthetic_library]

# The alib library is a pesudo library containing a DC generated 
# characterization of the target library. Generating this library can lead to
# better synthesis at the expense of extra build time on the first compile
set alib_library_analysis_path ${libs}/synopsys-alib/

# Generate the alib library if it does not already exist
alib_analyze_libs

# ------------------------------------------------------------------------------
# Associate libraries with min libraries
# ------------------------------------------------------------------------------

foreach max_lib [concat $stdcell_library(db,$slow_corner_pvt)] \
        min_lib [concat $stdcell_library(db,$fast_corner_pvt)] \
{
    set_min_library $max_lib -min_version $min_lib
}

# ------------------------------------------------------------------------------
# Create MW design library
# ------------------------------------------------------------------------------

# The Milkyway reference library contains the physical characteristics of the
# cells in the target libraries. By setting this variable, the search_path and 
# physical library will be enhanced to use Milkyway libraries.
set_app_var mw_reference_library [concat $stdcell_mw_library]

# This variable controls the folder dc_shell uses to save the Milkyway views of
# cells defined in the current design.
set_app_var mw_design_library ${BUILD_DIR}/$TOP/milkyway

create_mw_lib -technology $tech_file \
              -bus_naming_style {[%d]} \
              -mw_reference_library $mw_reference_library \
                                    $mw_design_library

open_mw_lib $mw_design_library

# Check consistency of logical vs. physical libraries
check_library

set_tlu_plus_files -max_tluplus $tluplus_file($slow_corner_extraction) \
                   -min_tluplus $tluplus_file($fast_corner_extraction) \
                   -tech2itf_map $tf2itf_map_file

check_tlu_plus_files
