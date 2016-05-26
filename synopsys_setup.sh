# Set up the Synopsys toolchain

mkdir -p ~/.modules   # this is just to fix a warning

### Setup the module scripts
export MODULESHOME=/usr/class/ee/modules/tcl
source $MODULESHOME/init/bash.in 

### Load the base toolchain
module load base
module load genesis2
module load vcs-mx
module load dc_shell

### Load Tool Env.
module load synopsys_edk #
module load cdesigner # Custom Designer
#module load cni # Pycell for layout Pcell ##### FIX ME! I crashes gcc
module load hercules # Hercules for DRC/LVS/LPE
module load starrc # Star-RCX for LPE
module load cx # Custom Explorer Waveform Viewer
module load synopsys_pdk # load env for synopsys 90nm PDK
module load icc # load ICC for place and route

### some helpful alias to make your life better
alias dve='dve -full64'
alias icc_shell="icc_shell -64bit"

### Queue If Licenses Are Unavailable
export SNPSLMD_QUEUE=true
export SNPS_MAX_WAITTIME=7200
export SNPS_MAX_QUEUETIME=7200

### Use gcc-4.4 for some reason
if [ -f /usr/bin/gcc-4.4 ]; then
export J_CC=gcc-4.4
else
export J_CC=gcc
fi
