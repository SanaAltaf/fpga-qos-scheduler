`timescale 1ns/1ps
//`include "qos_defines.v"

module tb_metrics;

    reg         clk_i;
    reg         rst_ni;

    reg         ms_tick_i;
    reg [31:0]  ms_count_i;

    reg         ev_safety_start_i;
    reg         ev_safety_done_i;
    reg         ev_ai_start_i;
    reg         ev_ai_done_i;
    reg [31:0]  ev_task_enq_ms_i;

    reg         wdg_event_i;
    reg [15:0]  wdg_event_count_i;
    reg         emergency_event_i;

    reg [2:0]   fifo_count_i;

    reg         rd_metrics_req_i;
    reg         set_param_valid_i;
    reg [7:0]   set_param_id_i;
    reg [31:0]  set_param_val_i;

    reg         tx_ready_i;
    wire [7:0]  tx_byte_o;
    wire        tx_valid_o;

    wire [15:0] cfg_stop_dist_o;
    wire [31:0] cfg_wdg_timeout_o;
    wire [31:0] cfg_telem_period_o;

    metrics dut (
        .clk_i(clk_i),
        .rst_ni(rst_ni),
        .ms_tick_i(ms_tick_i),
        .ms_count_i(ms_count_i),
        .ev_safety_start_i(ev_safety_start_i),
        .ev_safety_done_i(ev_safety_done_i),
        .ev_ai_start_i(ev_ai_start_i),
        .ev_ai_done_i(ev_ai_done_i),
        .ev_task_enq_ms_i(ev_task_enq_ms_i),
        .wdg_event_i(wdg_event_i),
        .wdg_event_count_i(wdg_event_count_i),
        .emergency_event_i(emergency_event_i),
        .fifo_count_i(fifo_count_i),
        .rd_metrics_req_i(rd_metrics_req_i),
        .set_param_valid_i(set_param_valid_i),
        .set_param_id_i(set_param_id_i),
        .set_param_val_i(set_param_val_i),
        .tx_ready_i(tx_ready_i),
        .tx_byte_o(tx_byte_o),
        .tx_valid_o(tx_valid_o),
        .cfg_stop_dist_o(cfg_stop_dist_o),
        .cfg_wdg_timeout_o(cfg_wdg_timeout_o),
        .cfg_telem_period_o(cfg_telem_period_o)
    );

    // Clock
    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    // Capture UART bytes
    reg [7:0] captured [0:39];
    integer cap_idx;

    always @(posedge clk_i) begin
        if (tx_valid_o) begin
            captured[cap_idx] <= tx_byte_o;
            cap_idx <= cap_idx + 1;
        end
    end

    task pulse_ms_tick;
    begin
        @(negedge clk_i);
        ms_tick_i = 1'b1;
        @(negedge clk_i);
        ms_tick_i = 1'b0;
    end
    endtask

    task pulse_safety_start(input [31:0] now_ms, input [31:0] enq_ms);
    begin
        @(negedge clk_i);
        ms_count_i         = now_ms;
        ev_task_enq_ms_i   = enq_ms;
        ev_safety_start_i  = 1'b1;
        @(negedge clk_i);
        ev_safety_start_i  = 1'b0;
    end
    endtask

    task pulse_ai_start;
    begin
        @(negedge clk_i);
        ev_ai_start_i = 1'b1;
        @(negedge clk_i);
        ev_ai_start_i = 1'b0;
    end
    endtask

    task pulse_emergency;
    begin
        @(negedge clk_i);
        emergency_event_i = 1'b1;
        @(negedge clk_i);
        emergency_event_i = 1'b0;
    end
    endtask

    task set_param(input [7:0] id, input [31:0] val);
    begin
        @(negedge clk_i);
        set_param_id_i    = id;
        set_param_val_i   = val;
        set_param_valid_i = 1'b1;
        @(negedge clk_i);
        set_param_valid_i = 1'b0;
    end
    endtask

    task request_metrics;
    begin
        @(negedge clk_i);
        rd_metrics_req_i = 1'b1;
        @(negedge clk_i);
        rd_metrics_req_i = 1'b0;
    end
    endtask

    initial begin
        // Init
        rst_ni            = 0;
        ms_tick_i         = 0;
        ms_count_i        = 0;
        ev_safety_start_i = 0;
        ev_safety_done_i  = 0;
        ev_ai_start_i     = 0;
        ev_ai_done_i      = 0;
        ev_task_enq_ms_i  = 0;
        wdg_event_i       = 0;
        wdg_event_count_i = 16'd0;
        emergency_event_i = 0;
        fifo_count_i      = 3'd0;
        rd_metrics_req_i  = 0;
        set_param_valid_i = 0;
        set_param_id_i    = 0;
        set_param_val_i   = 0;
        tx_ready_i        = 1'b1;
        cap_idx           = 0;

        // Reset
        repeat (3) @(negedge clk_i);
        rst_ni = 1'b1;
        repeat (2) @(negedge clk_i);

        // -------------------------
        // Test 1: SET_PARAM writes
        // -------------------------
        set_param(`PARAM_STOP_DIST,    32'd55);
        set_param(`PARAM_WDG_TIMEOUT,  32'd1234);
        set_param(`PARAM_TELEM_PERIOD, 32'd77);

        if (cfg_stop_dist_o   !== 16'd55)   $fatal(1, "cfg_stop_dist_o mismatch");
        if (cfg_wdg_timeout_o !== 32'd1234) $fatal(1, "cfg_wdg_timeout_o mismatch");
        if (cfg_telem_period_o!== 32'd77)   $fatal(1, "cfg_telem_period_o mismatch");

        // -------------------------
        // Test 2: counter / latency updates
        // -------------------------
        fifo_count_i = 3'd5;
        pulse_safety_start(32'd110, 32'd100);  // latency = 10
        pulse_safety_start(32'd125, 32'd120);  // latency = 5
        pulse_ai_start();
        pulse_emergency();
        wdg_event_count_i = 16'd9;

        // small settle
        repeat (2) @(negedge clk_i);

        if (dut.safety_task_count      !== 32'd2) $fatal(1, "safety_task_count mismatch");
        if (dut.ai_task_count          !== 32'd1) $fatal(1, "ai_task_count mismatch");
        if (dut.safety_lat_max_ms      !== 32'd10) $fatal(1, "safety_lat_max_ms mismatch");
        if (dut.safety_lat_sum_ms      !== 32'd15) $fatal(1, "safety_lat_sum_ms mismatch");
        if (dut.safety_lat_samples     !== 32'd2) $fatal(1, "safety_lat_samples mismatch");
        if (dut.safety_lat_avg_ms      !== 32'd7) $fatal(1, "safety_lat_avg_ms mismatch");
        if (dut.fifo_max_occupancy     !== 3'd5) $fatal(1, "fifo_max_occupancy mismatch");
        if (dut.emergency_event_count  !== 32'd1) $fatal(1, "emergency_event_count mismatch");

        // -------------------------
        // Test 3: READ_METRICS UART frame
        // -------------------------
        cap_idx = 0;
        request_metrics();

        // wait long enough to collect frame
        repeat (100) @(negedge clk_i);

        // Basic header checks
        if (captured[0] !== `FRAME_SOF) $fatal(1, "SOF mismatch");
        if (captured[1] !== 8'h20)      $fatal(1, "TYPE mismatch");
        if (captured[2] !== 8'd28)      $fatal(1, "LEN mismatch");

        // safety_task_count = 2
        if (captured[3] !== 8'h00 || captured[4] !== 8'h00 ||
            captured[5] !== 8'h00 || captured[6] !== 8'h02)
            $fatal(1, "safety_task_count bytes mismatch");

        // ai_task_count = 1
        if (captured[7] !== 8'h00 || captured[8] !== 8'h00 ||
            captured[9] !== 8'h00 || captured[10] !== 8'h01)
            $fatal(1, "ai_task_count bytes mismatch");

        // safety_lat_max_ms = 10
        if (captured[11] !== 8'h00 || captured[12] !== 8'h00 ||
            captured[13] !== 8'h00 || captured[14] !== 8'h0A)
            $fatal(1, "safety_lat_max_ms bytes mismatch");

        // safety_lat_avg_ms = 7
        if (captured[15] !== 8'h00 || captured[16] !== 8'h00 ||
            captured[17] !== 8'h00 || captured[18] !== 8'h07)
            $fatal(1, "safety_lat_avg_ms bytes mismatch");

        // fifo_max_occupancy = 5
        if (captured[19] !== 8'h00 || captured[20] !== 8'h00 ||
            captured[21] !== 8'h00 || captured[22] !== 8'h05)
            $fatal(1, "fifo_max_occupancy bytes mismatch");

        // wdg_event_count = 9
        if (captured[23] !== 8'h00 || captured[24] !== 8'h00 ||
            captured[25] !== 8'h00 || captured[26] !== 8'h09)
            $fatal(1, "wdg_event_count bytes mismatch");

        // emergency_event_count = 1
        if (captured[27] !== 8'h00 || captured[28] !== 8'h00 ||
            captured[29] !== 8'h00 || captured[30] !== 8'h01)
            $fatal(1, "emergency_event_count bytes mismatch");

        // CRC stub byte
        if (captured[31] !== 8'h00)
            $fatal(1, "CRC byte mismatch");

        $display("PASS: basic metrics testbench checks completed");
        $finish;
    end

endmodule