#!/bin/bash

set -e

for TOPO in MESH TORUS;
do
    for SIZE in 2;
    do
        for RATE in 12;
        do
            DIR=${TOPO}_${SIZE}_${RATE}
            cp -rf ./verif/mesh_generate ./verif/${DIR}

            sed -i "s/^parameter topology.*/parameter topology = \`TOPOLOGY_${TOPO}/" "./verif/${DIR}/parameters.v"
            sed -i "s/^parameter topo_width.*/parameter topo_width = ${SIZE};/" "./verif/${DIR}/parameters.v"
            sed -i "s/^parameter topo_height.*/parameter topo_height = ${SIZE};/" "./verif/${DIR}/parameters.v"

            sed -i "s/\sparameter packet_rate.*/parameter packet_rate = ${RATE};/" "./verif/${DIR}/testbench.v"

#            make TESTCASE=${DIR}
        done
    done
done


# for flatten butterfly
for SIZE in 2;
    do
        for RATE in 12;
        do
            DIR=FBFLY_${SIZE}_${RATE}
            cp -rf ./verif/fbfly_generate ./verif/${DIR}

            sed -i "s/^parameter topo_width.*/parameter topo_width = ${SIZE};/" "./verif/${DIR}/parameters.v"
            sed -i "s/^parameter topo_height.*/parameter topo_height = ${SIZE};/" "./verif/${DIR}/parameters.v"

            sed -i "s/\sparameter packet_rate.*/parameter packet_rate = ${RATE};/" "./verif/${DIR}/testbench.v"
#            make TESTCASE=FBFLY_${DIR}
        done
done
