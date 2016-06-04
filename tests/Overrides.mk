$(BUILD)/mesh4x4/rate_12.simv: \
	VCS_OPTIONS += 	-pvalue+testbench/packet_rate=12
$(BUILD)/mesh4x4/rate_25.simv: \
	VCS_OPTIONS += 	-pvalue+testbench/packet_rate=25
$(BUILD)/mesh4x4/rate_37.simv: \
	VCS_OPTIONS +=	-pvalue+testbench/packet_rate=37
$(BUILD)/mesh4x4/rate_50.simv: \
	VCS_OPTIONS +=	-pvalue+testbench/packet_rate=50

tests/mesh4x4/rate_%.v: tests/mesh4x4/testbench.v
	cp $^ $@

$(BUILD)/torus4x4/rate_12.simv: \
	VCS_OPTIONS +=	-pvalue+testbench/topology=1 \
					-pvalue+testbench/packet_rate=12
$(BUILD)/torus4x4/rate_25.simv: \
	VCS_OPTIONS +=	-pvalue+testbench/topology=1 \
				    -pvalue+testbench/packet_rate=25
$(BUILD)/torus4x4/rate_37.simv: \
	VCS_OPTIONS +=	-pvalue+testbench/topology=1 \
	                -pvalue+testbench/packet_rate=37
$(BUILD)/torus4x4/rate_50.simv: \
	VCS_OPTIONS +=	-pvalue+testbench/topology=1 \
	                -pvalue+testbench/packet_rate=50

tests/torus4x4/rate_%.v: tests/torus4x4/testbench.v
	cp $^ $@

$(BUILD)/fbfly4x4/rate_12.simv: \
	VCS_OPTIONS +=	-pvalue+testbench/topology=2 \
					-pvalue+testbench/packet_rate=12
$(BUILD)/fbfly4x4/rate_25.simv: \
	VCS_OPTIONS +=	-pvalue+testbench/topology=2 \
				    -pvalue+testbench/packet_rate=25
$(BUILD)/fbfly4x4/rate_37.simv: \
	VCS_OPTIONS +=	-pvalue+testbench/topology=2 \
	                -pvalue+testbench/packet_rate=37
$(BUILD)/fbfly4x4/rate_50.simv: \
	VCS_OPTIONS +=	-pvalue+testbench/topology=2 \
	                -pvalue+testbench/packet_rate=50

tests/fbfly4x4/rate_%.v: tests/fbfly4x4/testbench.v
	cp $^ $@
