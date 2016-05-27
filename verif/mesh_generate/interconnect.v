module interconnect(clk, reset, injection_channels, injection_flow_ctrl, ejection_channels, ejection_flow_ctrl);

`include "c_functions.v"
`include "c_constants.v"
`include "rtr_constants.v"
`include "vcr_constants.v"
`include "parameters.v"

   // total number of packet classes
   localparam num_packet_classes = num_message_classes * num_resource_classes;
   
   // number of VCs
   localparam num_vcs = num_packet_classes * num_vcs_per_class;
   
   // width required to select individual VC
   localparam vc_idx_width = clogb(num_vcs);

   // total number of routers
   localparam num_routers
     = (num_nodes + num_nodes_per_router - 1) / num_nodes_per_router;
 
   // number of routers in each dimension
   localparam num_routers_per_dim = croot(num_routers, num_dimensions);
   
   // width required to select individual router in a dimension
   localparam dim_addr_width = clogb(num_routers_per_dim);
   
   // width required to select individual router in entire network
   localparam router_addr_width = num_dimensions * dim_addr_width;
   
   // width of flow control signals
   localparam flow_ctrl_width
     = (flow_ctrl_type == `FLOW_CTRL_TYPE_CREDIT) ? (1 + vc_idx_width) :
       -1;
   
   // width of link management signals
   localparam link_ctrl_width = enable_link_pm ? 1 : 0;
   
   // width of flit control signals
   localparam flit_ctrl_width
     = (packet_format == `PACKET_FORMAT_HEAD_TAIL) ? 
       (1 + vc_idx_width + 1 + 1) : 
       (packet_format == `PACKET_FORMAT_TAIL_ONLY) ? 
       (1 + vc_idx_width + 1) : 
       (packet_format == `PACKET_FORMAT_EXPLICIT_LENGTH) ? 
       (1 + vc_idx_width + 1) : 
       -1;
   
   // channel width
   localparam channel_width
     = link_ctrl_width + flit_ctrl_width + flit_data_width;

    // input ports
    input clk;
    input reset;

	//wires that are connected to the flit_sink and packet_source modules
    input [0:(num_routers*channel_width)-1] injection_channels;
    input [0:(num_routers*flow_ctrl_width)-1] injection_flow_ctrl;
    output [0:(num_routers*channel_width)-1] ejection_channels;
    output [0:(num_routers*flow_ctrl_width)-1] ejection_flow_ctrl;

    wire [0:num_routers-1]				    rtr_error;

    genvar i;
    generate
        for (i = 0; i < num_routers; i = i + 1)
        begin: rtr_wires

            //wires that are directly conected to the channel/flow_ctrl ports of each router
            wire[0:channel_width - 1] channel_op_0;
            wire[0:channel_width - 1] channel_op_1;
            wire[0:channel_width - 1] channel_op_2;
            wire[0:channel_width - 1] channel_op_3;
            wire[0:channel_width - 1] channel_op_4;

            wire[0:channel_width - 1] channel_ip_0;
            wire[0:channel_width - 1] channel_ip_1;
            wire[0:channel_width - 1] channel_ip_2;
            wire[0:channel_width - 1] channel_ip_3;
            wire[0:channel_width - 1] channel_ip_4;

            wire[0:flow_ctrl_width - 1] flow_ctrl_ip_0;
            wire[0:flow_ctrl_width - 1] flow_ctrl_ip_1;
            wire[0:flow_ctrl_width - 1] flow_ctrl_ip_2;
            wire[0:flow_ctrl_width - 1] flow_ctrl_ip_3;
            wire[0:flow_ctrl_width - 1] flow_ctrl_ip_4;

            wire[0:flow_ctrl_width - 1] flow_ctrl_op_0;
            wire[0:flow_ctrl_width - 1] flow_ctrl_op_1;
            wire[0:flow_ctrl_width - 1] flow_ctrl_op_2;
            wire[0:flow_ctrl_width - 1] flow_ctrl_op_3;
            wire[0:flow_ctrl_width - 1] flow_ctrl_op_4;

            assign channel_ip_4 = injection_channels[i*channel_width:((i+1)*channel_width)-1];
            assign flow_ctrl_op_4 = ejection_flow_ctrl[i*flow_ctrl_width:((i+1)*flow_ctrl_width)-1];
            
            assign injection_flow_ctrl[i*flow_ctrl_width:((i+1)*flow_ctrl_width)-1] = flow_ctrl_ip_4;
            assign ejection_channels[i*channel_width:((i+1)*channel_width)-1] = channel_op_4;



            wire [0:router_addr_width-1] router_address;
            
            wire [31:0] x_addr = i % topo_width;
            wire [31:0] y_addr = i / topo_width;
            assign router_address[0:(router_addr_width-1)/2] = x_addr[(router_addr_width-1)/2:0];
            assign router_address[router_addr_width/2:router_addr_width-1] = y_addr[(router_addr_width-1)/2:0];

            router_wrap
                #(.topology(topology),
                  .buffer_size(buffer_size),
                  .num_message_classes(num_message_classes),
                  .num_resource_classes(num_resource_classes),
                  .num_vcs_per_class(num_vcs_per_class),
                  .num_nodes(num_nodes),
                  .num_dimensions(num_dimensions),
                  .num_nodes_per_router(num_nodes_per_router),
                  .packet_format(packet_format),
                  .flow_ctrl_type(flow_ctrl_type),
                  .flow_ctrl_bypass(flow_ctrl_bypass),
                  .max_payload_length(max_payload_length),
                  .min_payload_length(min_payload_length),
                  .router_type(router_type),
                  .enable_link_pm(enable_link_pm),
                  .flit_data_width(flit_data_width),
                  .error_capture_mode(error_capture_mode),
                  .restrict_turns(restrict_turns),
                  .predecode_lar_info(predecode_lar_info),
                  .routing_type(routing_type),
                  .dim_order(dim_order),
                  .input_stage_can_hold(input_stage_can_hold),
                  .fb_regfile_type(fb_regfile_type),
                  .fb_mgmt_type(fb_mgmt_type),
                  .explicit_pipeline_register(explicit_pipeline_register),
                  .dual_path_alloc(dual_path_alloc),
                  .dual_path_allow_conflicts(dual_path_allow_conflicts),
                  .dual_path_mask_on_ready(dual_path_mask_on_ready),
                  .precomp_ivc_sel(precomp_ivc_sel),
                  .precomp_ip_sel(precomp_ip_sel),
                  .elig_mask(elig_mask),
                  .vc_alloc_type(vc_alloc_type),
                  .vc_alloc_arbiter_type(vc_alloc_arbiter_type),
                  .vc_alloc_prefer_empty(vc_alloc_prefer_empty),
                  .sw_alloc_type(sw_alloc_type),
                  .sw_alloc_arbiter_type(sw_alloc_arbiter_type),
                  .sw_alloc_spec_type(sw_alloc_spec_type),
                  .crossbar_type(crossbar_type),
                  .reset_type(reset_type))
            rtr_wrap
                (.clk(clk),
                 .reset(reset),
                 .router_address(router_address),
                 .channel_in_ip({channel_ip_0, channel_ip_1, channel_ip_2, channel_ip_3, channel_ip_4}),
                 .flow_ctrl_out_ip({ flow_ctrl_ip_0, flow_ctrl_ip_1, flow_ctrl_ip_2, flow_ctrl_ip_3, flow_ctrl_ip_4 }),
                 .channel_out_op({ channel_op_0, channel_op_1, channel_op_2, channel_op_3, channel_op_4 }),
                 .flow_ctrl_in_op({ flow_ctrl_op_0, flow_ctrl_op_1, flow_ctrl_op_2, flow_ctrl_op_3, flow_ctrl_op_4 }),
                 .error(rtr_error[i]));
        end
    endgenerate

    genvar j;
    generate
        for (j = 0; j < num_routers; j = j + 1)
        begin: connect
            if (j % topo_width == 0) // left edge
            begin
                if (topology == `TOPOLOGY_MESH) // mesh
                begin
                    assign rtr_wires[j].channel_ip_0 = {channel_width{1'b0}};
                    assign rtr_wires[j].flow_ctrl_op_0 = {flow_ctrl_width{1'b0}};
                end
                else    // torus
                begin
                    assign rtr_wires[j].channel_ip_0 = rtr_wires[j + topo_width - 1].channel_op_1;
                    assign rtr_wires[j].flow_ctrl_op_0 = rtr_wires[j + topo_width - 1].flow_ctrl_ip_1;
                end
            end
            else
            begin
                assign rtr_wires[j].channel_ip_0 = rtr_wires[j-1].channel_op_1;
                assign rtr_wires[j].flow_ctrl_op_0 = rtr_wires[j-1].flow_ctrl_ip_1;
            end
            
            if (j % topo_width == topo_width - 1) // right edge
                begin
                    if (topology == `TOPOLOGY_MESH) // mesh
                    begin
                        assign rtr_wires[j].channel_ip_1 = {channel_width{1'b0}};
                        assign rtr_wires[j].flow_ctrl_op_1 = {flow_ctrl_width{1'b0}};
                    end
                    else    // torus
                    begin
                        assign rtr_wires[j].channel_ip_1 = rtr_wires[j - topo_width + 1].channel_op_0;
                        assign rtr_wires[j].flow_ctrl_op_1 = rtr_wires[j - topo_width + 1].flow_ctrl_ip_0;
                    end
                end
            else
            begin
                assign rtr_wires[j].channel_ip_1 = rtr_wires[j+1].channel_op_0;
                assign rtr_wires[j].flow_ctrl_op_1 = rtr_wires[j+1].flow_ctrl_ip_0;
            end

            if (j < topo_width) // top edge
                begin
                    if (topology == `TOPOLOGY_MESH)  // mesh
                    begin
                        assign rtr_wires[j].channel_ip_2 = {channel_width{1'b0}};
                        assign rtr_wires[j].flow_ctrl_op_2 = {flow_ctrl_width{1'b0}};
                    end
                    else    // torus
                    begin
                        assign rtr_wires[j].channel_ip_2 = rtr_wires[(topo_height - 1) * topo_width + j].channel_op_3;
                        assign rtr_wires[j].flow_ctrl_op_2 = rtr_wires[(topo_height - 1) * topo_width + j].flow_ctrl_ip_3;
                    end
                end
            else
            begin
                assign rtr_wires[j].channel_ip_2 = rtr_wires[j-topo_width].channel_op_3;
                assign rtr_wires[j].flow_ctrl_op_2 = rtr_wires[j-topo_width].flow_ctrl_ip_3;
            end

            if (j >= (topo_height - 1)*topo_width)  // bottom edge
                begin
                    if (topology == `TOPOLOGY_MESH)  // mesh
                    begin
                        assign rtr_wires[j].channel_ip_3 = {channel_width{1'b0}};
                        assign rtr_wires[j].flow_ctrl_op_3 = {flow_ctrl_width{1'b0}};
                    end
                    else    // torus
                    begin
                        assign rtr_wires[j].channel_ip_3 = rtr_wires[j % topo_width].channel_op_2;
                        assign rtr_wires[j].flow_ctrl_op_3 = rtr_wires[j % topo_width].flow_ctrl_ip_2;
                    end
                end
            else
            begin
                assign rtr_wires[j].channel_ip_3 = rtr_wires[j+topo_width].channel_op_2;
                assign rtr_wires[j].flow_ctrl_op_3 = rtr_wires[j+topo_width].flow_ctrl_ip_2;
            end
        end
    endgenerate

    // connected together channels and flow_ctrl
    //assign rtr_wires[0].channel_ip_0 = {channel_width{1'b0}};
    //assign rtr_wires[0].channel_ip_1 = rtr_wires[1].channel_op_0;
    //assign rtr_wires[0].channel_ip_2 = {channel_width{1'b0}};
    //assign rtr_wires[0].channel_ip_3 = {channel_width{1'b0}};
    //assign rtr_wires[0].channel_ip_4 = injection_channels[0*channel_width:(1*channel_width)-1];
    //assign rtr_wires[0].flow_ctrl_op_0 = {flow_ctrl_width{1'b0}};
    //assign rtr_wires[0].flow_ctrl_op_1 = rtr_wires[1].flow_ctrl_ip_0;
    //assign rtr_wires[0].flow_ctrl_op_2 = {flow_ctrl_width{1'b0}};
    //assign rtr_wires[0].flow_ctrl_op_3 = {flow_ctrl_width{1'b0}};
    //assign rtr_wires[0].flow_ctrl_op_4 = ejection_flow_ctrl[0*flow_ctrl_width:(1*flow_ctrl_width)-1];

    //assign rtr_wires[1].channel_ip_0 = rtr_wires[0].channel_op_1;
    //assign rtr_wires[1].channel_ip_1 = {channel_width{1'b0}};
    //assign rtr_wires[1].channel_ip_2 = {channel_width{1'b0}};
    //assign rtr_wires[1].channel_ip_3 = {channel_width{1'b0}};
    //assign rtr_wires[1].channel_ip_4 = injection_channels[1*channel_width:(2*channel_width)-1];
    //assign rtr_wires[1].flow_ctrl_op_0 = rtr_wires[0].flow_ctrl_ip_1;
    //assign rtr_wires[1].flow_ctrl_op_1 = {flow_ctrl_width{1'b0}};
    //assign rtr_wires[1].flow_ctrl_op_2 = {flow_ctrl_width{1'b0}};
    //assign rtr_wires[1].flow_ctrl_op_3 = {flow_ctrl_width{1'b0}};
    //assign rtr_wires[1].flow_ctrl_op_4 = ejection_flow_ctrl[1*flow_ctrl_width:(2*flow_ctrl_width)-1];

	//assign injection_flow_ctrl[0*flow_ctrl_width:(1*flow_ctrl_width)-1] = rtr_wires[0].flow_ctrl_ip_4;
	//assign ejection_channels[0*channel_width:(1*channel_width)-1] = rtr_wires[0].channel_op_4;

	//assign injection_flow_ctrl[1*flow_ctrl_width:(2*flow_ctrl_width)-1] = rtr_wires[1].flow_ctrl_ip_4;
	//assign ejection_channels[1*channel_width:(2*channel_width)-1] = rtr_wires[1].channel_op_4;


	// routers currently connected as a 3X3 mesh
endmodule
