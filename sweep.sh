#!/bin/bash

set -e

for TOPO in MESH TORUS;
do
    sed -i "s/^parameter topology.*/parameter topology = \`TOPOLOGY_${TOPO}/" "./verif/mesh_generate/parameters.v"

    for SIZE in 2 4 6;
    do
        sed -i "s/^parameter topo_width.*/parameter topo_width = ${SIZE};/" "./verif/mesh_generate/parameters.v"
        sed -i "s/^parameter topo_height.*/parameter topo_height = ${SIZE};/" "./verif/mesh_generate/parameters.v"

        for RATE in 12 25 37 50;
        do
            sed -i "s/^parameter packet_rate.*/parameter packet_rate = ${RATE};/" "./verif/mesh_generate/parameters.v"

            make TESTCASE=${TOPO}_${SIZE}_${RATE}
        done
    done
done


# for flatten butterfly
for SIZE in 2 4 6;
    do
        sed -i "s/^parameter topo_width.*/parameter topo_width = ${SIZE};/" "./verif/fbfly_generate/parameters.v"
        sed -i "s/^parameter topo_height.*/parameter topo_height = ${SIZE};/" "./verif/fbfly_generate/parameters.v"

        for RATE in 12 25 37 50;
        do
            sed -i "s/^parameter packet_rate.*/parameter packet_rate = ${RATE};/" "./verif/fbfly_generate/parameters.v"

            make TESTCASE=FBFLY_${SIZE}_${RATE}
        done
done
