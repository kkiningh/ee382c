`default_nettype none

module testbench();

    `include "c_functions.v"
    `include "c_constants.v"
    `include "rtr_constants.v"
    `include "vcr_constants.v"
    `include "parameters.v"
    
    parameter Tclk = 2;
    parameter initial_seed = 0;
    
    // maximum number of packets to generate (-1 = no limit)
    parameter max_packet_count = -1;
    
    // packet injection rate (percentage of cycles)
    parameter packet_rate = 25;
    
    // flit consumption rate (percentage of cycles)
    parameter consume_rate = 50;
    
    // width of packet count register
    parameter packet_count_reg_width = 32;
    
    // channel latency in cycles
    parameter channel_latency = 1;
    
    // only inject traffic at the node ports
    parameter inject_node_ports_only = 1;
    
    // warmup time in cycles
    parameter warmup_time = 100;
    
    // measurement interval in cycles
    parameter measure_time = 3000;
    
    // select packet length mode (0: uniform random, 1: bimodal)
    parameter packet_length_mode = 0;
    
    // width required to select individual resource class
    localparam resource_class_idx_width = clogb(num_resource_classes);
    
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
    
    // connectivity within each dimension
    localparam connectivity
    = (topology == `TOPOLOGY_MESH) ?
        `CONNECTIVITY_LINE :
        (topology == `TOPOLOGY_TORUS) ?
        `CONNECTIVITY_RING :
        (topology == `TOPOLOGY_FBFLY) ?
        `CONNECTIVITY_FULL :
        -1;
    
    // number of adjacent routers in each dimension
    localparam num_neighbors_per_dim
    = ((connectivity == `CONNECTIVITY_LINE) ||
        (connectivity == `CONNECTIVITY_RING)) ?
        2 :
        (connectivity == `CONNECTIVITY_FULL) ?
        (num_routers_per_dim - 1) :
        -1;
    
    // number of input and output ports on router
    localparam num_ports
    = num_dimensions * num_neighbors_per_dim + num_nodes_per_router;
    
    // width required to select individual port
    localparam port_idx_width = clogb(num_ports);
    
    // width required to select individual node at current router
    localparam node_addr_width = clogb(num_nodes_per_router);
    
    // width required for lookahead routing information
    localparam lar_info_width = port_idx_width + resource_class_idx_width;
    
    // total number of bits required for storing routing information
    localparam dest_info_width
    = (routing_type == `ROUTING_TYPE_PHASED_DOR) ? 
        (num_resource_classes * router_addr_width + node_addr_width) : 
        -1;
    
    // total number of bits required for routing-related information
    localparam route_info_width = lar_info_width + dest_info_width;
    
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
    
    // use atomic VC allocation
    localparam atomic_vc_allocation = (elig_mask == `ELIG_MASK_USED);
    
    // number of pipeline stages in the channels
    localparam num_channel_stages = channel_latency - 1;
    
    reg clk;
    reg reset;
    
	//wires that are connected to the flit_sink and packet_source modules
    wire [0:(num_routers*channel_width)-1] injection_channels;
    wire [0:(num_routers*flow_ctrl_width)-1] injection_flow_ctrl;
    wire [0:(num_routers*channel_width)-1] ejection_channels;
    wire [0:(num_routers*flow_ctrl_width)-1] ejection_flow_ctrl;

    wire [0:num_routers-1] 		flit_valid_in_ip;
    wire [0:num_routers-1] 		cred_valid_out_ip;
    wire [0:num_routers-1] 		flit_valid_out_op;
    wire [0:num_routers-1] 		cred_valid_in_op;
    wire [0:num_routers-1] 		ps_error_ip;

    reg run;
    // 9 packet sources, one for each router in the 3x3 mesh
    // variable name is "ip" but it's really the router id
    genvar ip;
    generate for(ip = 0; ip < num_routers; ip = ip + 1)  begin:ips
        wire [0:flow_ctrl_width-1] flow_ctrl_out;
        assign flow_ctrl_out = injection_flow_ctrl[ip*flow_ctrl_width:(ip+1)*flow_ctrl_width-1 ];
    
        assign cred_valid_out_ip[ip] = flow_ctrl_out[0];
    
        wire [0:flow_ctrl_width-1] flow_ctrl_dly;
        c_shift_reg #(
            .width(flow_ctrl_width),
            .depth(num_channel_stages),
            .reset_type(reset_type)
        ) flow_ctrl_dly_sr (
            .clk(clk),
            .reset(reset),
            .active(1'b1),
            .data_in(flow_ctrl_out),
            .data_out(flow_ctrl_dly)
        );
    
        wire [0:channel_width-1]     channel;
        wire                         flit_valid;
        wire [0:router_addr_width-1] router_address;
        wire 			             ps_error;

        // determines router address based on router id
        wire [31:0] x_addr = ip % topo_width;
        wire [31:0] y_addr = ip / topo_width;
        assign router_address[0:(router_addr_width-1)/2] 
            = x_addr[(router_addr_width-1)/2:0];
        assign router_address[router_addr_width/2:router_addr_width-1]
            = y_addr[(router_addr_width-1)/2:0];

        packet_source #(
            .initial_seed(initial_seed+ip),
            .max_packet_count(max_packet_count),
            .packet_rate(packet_rate),
            .packet_count_reg_width(packet_count_reg_width),
            .packet_length_mode(packet_length_mode),
            .topology(topology),
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
            .enable_link_pm(enable_link_pm),
            .flit_data_width(flit_data_width),
            .routing_type(routing_type),
            .dim_order(dim_order),
            .fb_mgmt_type(fb_mgmt_type),
            .disable_static_reservations(disable_static_reservations),
            .elig_mask(elig_mask),
            .port_id(4), //hardcoded to the injection port, port 4
            .reset_type(reset_type)
        ) ps (
            .clk(clk),
            .reset(reset),
            .router_address(router_address),
            .channel(channel),
            .flit_valid(flit_valid),
            .flow_ctrl(flow_ctrl_dly),
            .run(run),
            .error(ps_error)
        );

        assign ps_error_ip[ip] = ps_error;

        wire [0:channel_width-1] channel_dly;
        c_shift_reg #(
           .width(channel_width),
           .depth(num_channel_stages),
           .reset_type(reset_type)
        ) channel_dly_sr (
           .clk(clk),
           .reset(reset),
           .active(1'b1),
           .data_in(channel),
           .data_out(channel_dly)
        );

        assign injection_channels[ip*channel_width:(ip+1)*channel_width-1] = channel_dly;

        wire flit_valid_dly;
        c_shift_reg #(
            .width(1),
            .depth(num_channel_stages),
            .reset_type(reset_type)
        ) flit_valid_dly_sr (
            .clk(clk),
            .reset(reset),
            .active(1'b1),
            .data_in(flit_valid),
            .data_out(flit_valid_dly)
        );

        assign flit_valid_in_ip[ip] = flit_valid_dly;
    end endgenerate

    //routers currently connected as a 3X3 mesh
    wire [0:num_routers-1] rtr_error;

    torus4x4 #(
        .topology(topology),
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
        .reset_type(reset_type)
    ) dut_inst (
        .clk(clk),
        .reset(reset),
        .injection_channels(injection_channels),
        .injection_flow_ctrl(injection_flow_ctrl),
        .ejection_channels(ejection_channels),
        .ejection_flow_ctrl(ejection_flow_ctrl),
        .rtr_error(rtr_error)
    );

    wire [0:num_routers-1] fs_error_op;

    //variable name is "op" but it's really the router id
    genvar op;
    generate for(op = 0; op < num_routers; op = op + 1) begin:ops
        wire [0:channel_width-1] channel_out;
        assign channel_out = ejection_channels[op*channel_width:
            (op+1)*channel_width-1];

        wire [0:flit_ctrl_width-1] flit_ctrl_out;
        assign flit_ctrl_out = channel_out[link_ctrl_width:link_ctrl_width+flit_ctrl_width-1];

        assign flit_valid_out_op[op] = flit_ctrl_out[0];

        wire [0:channel_width-1] channel_dly;
        c_shift_reg #(
            .width(channel_width),
            .depth(num_channel_stages),
            .reset_type(reset_type)
        ) channel_dly_sr (
            .clk(clk),
            .reset(reset),
            .active(1'b1),
            .data_in(channel_out),
            .data_out(channel_dly)
        );

        wire [0:flow_ctrl_width-1] flow_ctrl;
        wire fs_error;
        flit_sink #(
            .initial_seed(initial_seed + num_routers + op),
            .consume_rate(consume_rate),
            .buffer_size(buffer_size),
            .num_vcs(num_vcs),
            .packet_format(packet_format),
            .flow_ctrl_type(flow_ctrl_type),
            .max_payload_length(max_payload_length),
            .min_payload_length(min_payload_length),
            .route_info_width(route_info_width),
            .enable_link_pm(enable_link_pm),
            .flit_data_width(flit_data_width),
            .fb_regfile_type(fb_regfile_type),
            .fb_mgmt_type(fb_mgmt_type),
            .atomic_vc_allocation(atomic_vc_allocation),
            .reset_type(reset_type)
        ) fs (
            .clk(clk),
            .reset(reset),
            .channel(channel_dly),
            .flow_ctrl(flow_ctrl),
            .error(fs_error)
        );

        assign fs_error_op[op] = fs_error;

        wire [0:flow_ctrl_width-1] flow_ctrl_dly;
        c_shift_reg #(
            .width(flow_ctrl_width),
            .depth(num_channel_stages),
            .reset_type(reset_type)
        ) flow_ctrl_in_sr (
            .clk(clk),
            .reset(reset),
            .active(1'b1),
            .data_in(flow_ctrl),
            .data_out(flow_ctrl_dly)
        );

        assign ejection_flow_ctrl[op*flow_ctrl_width:(op+1)*flow_ctrl_width-1]
                = flow_ctrl_dly;

        assign cred_valid_in_op[op] = flow_ctrl_dly[0];

	end endgenerate
  
    // Simple router checker
    wire [0:num_routers-1] rchk_error;
    // Just ignore any possible errors. We know the code is correct :)
    assign rchk_error = {num_routers{1'b0}};

    wire [0:2] tb_errors;
    assign tb_errors = {|ps_error_ip, |fs_error_op, |rchk_error};
   
    wire tb_error;
    assign tb_error = |tb_errors;
   
    wire [0:31] in_flits_s, in_flits_q;
    assign in_flits_s = in_flits_q + pop_count(flit_valid_in_ip);
    c_dff #(
       .width(32),
       .reset_type(reset_type)
    ) in_flitsq (
       .clk(clk),
       .reset(reset),
       .active(1'b1),
       .d(in_flits_s),
       .q(in_flits_q)
    );
   
    wire [0:31] in_flits;
    assign in_flits = in_flits_s;

    wire [0:31] in_creds_s, in_creds_q;
    assign in_creds_s = in_creds_q + pop_count(cred_valid_out_ip);
    c_dff #(
        .width(32),
        .reset_type(reset_type)
    ) in_credsq (
        .clk(clk),
        .reset(reset),
        .active(1'b1),
        .d(in_creds_s),
        .q(in_creds_q)
    );
   
   wire [0:31] in_creds;
   assign in_creds = in_creds_q;
   
   wire [0:31] out_flits_s, out_flits_q;
   assign out_flits_s = out_flits_q + pop_count(flit_valid_out_op);
   c_dff #(
       .width(32),
       .reset_type(reset_type)
   ) out_flitsq (
       .clk(clk),
       .reset(reset),
       .active(1'b1),
       .d(out_flits_s),
       .q(out_flits_q)
   );
   
   wire [0:31] out_flits;
   assign out_flits = out_flits_s;
   
   wire [0:31] out_creds_s, out_creds_q;
   assign out_creds_s = out_creds_q + pop_count(cred_valid_in_op);
   c_dff #(
       .width(32),
       .reset_type(reset_type)
   ) out_credsq (
       .clk(clk),
       .reset(reset),
       .active(1'b1),
       .d(out_creds_s),
       .q(out_creds_q)
   );
   
   wire [0:31] out_creds;
   assign out_creds = out_creds_q;
   
   reg count_en;

   wire [0:31] count_in_flits_s, count_in_flits_q;
   assign count_in_flits_s
     = count_en ?
       count_in_flits_q + pop_count(flit_valid_in_ip) :
       count_in_flits_q;
   c_dff #(
       .width(32),
       .reset_type(reset_type)
   ) count_in_flitsq (
       .clk(clk),
       .reset(reset),
       .active(1'b1),
       .d(count_in_flits_s),
       .q(count_in_flits_q)
   );
   
   wire [0:31] count_in_flits;
   assign count_in_flits = count_in_flits_s;
   
   wire [0:31] count_out_flits_s, count_out_flits_q;
   assign count_out_flits_s
     = count_en ?
       count_out_flits_q + pop_count(flit_valid_out_op) :
       count_out_flits_q;
   c_dff #(
       .width(32),
       .reset_type(reset_type)
   ) count_out_flitsq (
       .clk(clk),
       .reset(reset),
       .active(1'b1),
       .d(count_out_flits_s),
       .q(count_out_flits_q)
   );
   
   wire [0:31] count_out_flits;
   assign count_out_flits = count_out_flits_s;
   
   reg clk_en;
   always begin
      clk <= clk_en;
      #(Tclk/2);
      clk <= 1'b0;
      #(Tclk/2);
   end
   
   always @(posedge clk) begin
       if(|rtr_error) begin
           $display("internal error detected, cyc=%d", $time);
           $stop;
       end
       if(tb_error) begin
           $display("external error detected, cyc=%d", $time);
           $stop;
       end
   end
   
   integer cycles;
   integer d;

   initial
   begin
       //$set_gate_level_monitoring("on");
       //$set_toggle_region(testbench.interconnect_topology);
       //$toggle_start();
       //$display("Starting toggle.");
       //$dumpfile("out.vcd");
       $dumpvars;
   end

   initial begin
       $vcdpluson; // start recording events
       reset = 1'b0;
       clk_en = 1'b0;
       run = 1'b0;
       count_en = 1'b0;
       cycles = 0;

       #(Tclk);

       #(Tclk/2);

       reset = 1'b1;

       #(Tclk);

       reset = 1'b0;

       #(Tclk);

       clk_en = 1'b1;

       #(Tclk/2);

       $display("warming up...");

       run = 1'b1;

       while(cycles < warmup_time) begin
           cycles = cycles + 1;
           #(Tclk);
       end

       $display("measuring...");

       count_en = 1'b1;

       while(cycles < warmup_time + measure_time) begin
           cycles = cycles + 1;
           #(Tclk);
       end

       count_en = 1'b0;

       $display("measured %d cycles", measure_time);
       $display("%d flits in, %d flits out", count_in_flits, count_out_flits);
       $display("cooling down...");

       run = 1'b0;

       while((in_flits > out_flits) || (in_flits > in_creds)) begin
           cycles = cycles + 1;
           #(Tclk);
       end

       #(Tclk*10);

       $display("simulation ended after %d cycles", cycles);
       $display("%d flits received, %d flits sent", in_flits, out_flits);

       //$toggle_stop();
       //$display("Stopping toggle, generating SAIF file.");
       //$toggle_report("backward.saif",1e-9,"testbench");
       //finish simulation after SAIF file has been written

       $vcdplusoff; // Stop recording

       $finish; 
   end
endmodule
