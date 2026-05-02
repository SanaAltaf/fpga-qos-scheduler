// =============================================================================
// FILE: metrics.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Person Diego
// =============================================================================

`timescale 1ns/1ps
`include "qos_defines.v"

module metrics (
    input  wire        clk_i,
    input  wire        rst_ni,

    input  wire        ms_tick_i,
    input  wire [31:0] ms_count_i,

    // Scheduler events
    input  wire        ev_safety_start_i,
    input  wire        ev_safety_done_i,
    input  wire        ev_ai_start_i,
    input  wire        ev_ai_done_i,
    input  wire [31:0] ev_task_enq_ms_i,

    // Watchdog / safety
    input  wire        wdg_event_i,
    input  wire [15:0] wdg_event_count_i,
    input  wire        emergency_event_i,

    // FIFO occupancy
    input  wire [2:0]  fifo_count_i,

    // Host commands
    input  wire        rd_metrics_req_i,
    input  wire        set_param_valid_i,
    input  wire [7:0]  set_param_id_i,
    input  wire [31:0] set_param_val_i,

    // UART TX
    input  wire        tx_ready_i,
    output reg  [7:0]  tx_byte_o,
    output reg         tx_valid_o,

    // Runtime config outputs
    output reg  [15:0] cfg_stop_dist_o,
    output reg  [31:0] cfg_wdg_timeout_o,
    output reg  [31:0] cfg_telem_period_o
);

    // -------------------------------------------------------------------------
    // Config registers (initialized to defaults)
    // -------------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            cfg_stop_dist_o    <= `STOP_DIST_CM_DEFAULT;
            cfg_wdg_timeout_o  <= `AI_WDG_TIMEOUT_MS_DEF;
            cfg_telem_period_o <= `TELEM_PERIOD_MS_DEF;
        end else if (set_param_valid_i) begin
            case (set_param_id_i)
                `PARAM_STOP_DIST:    cfg_stop_dist_o    <= set_param_val_i[15:0];
                `PARAM_WDG_TIMEOUT:  cfg_wdg_timeout_o  <= set_param_val_i;
                `PARAM_TELEM_PERIOD: cfg_telem_period_o <= set_param_val_i;
                default: ;
            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Performance counters
    // -------------------------------------------------------------------------
    reg [31:0] safety_task_count;
    reg [31:0] ai_task_count;
    reg [31:0] safety_lat_max_ms;
    reg [31:0] safety_lat_sum_ms;
    reg [31:0] safety_lat_samples;
    reg [2:0]  fifo_max_occupancy;
    reg [31:0] emergency_event_count;

    // Latency computation (registered for timing closure)
    reg [31:0] cur_lat;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            safety_task_count    <= 32'd0;
            ai_task_count        <= 32'd0;
            safety_lat_max_ms    <= 32'd0;
            safety_lat_sum_ms    <= 32'd0;
            safety_lat_samples   <= 32'd0;
            fifo_max_occupancy   <= 3'd0;
            emergency_event_count <= 32'd0;
            cur_lat              <= 32'd0;
        end else begin
            // Safety task started → compute latency
            if (ev_safety_start_i) begin
                safety_task_count <= safety_task_count + 32'd1;
                cur_lat           <= ms_count_i - ev_task_enq_ms_i;
                safety_lat_samples <= safety_lat_samples + 32'd1;
                safety_lat_sum_ms  <= safety_lat_sum_ms +
                                      (ms_count_i - ev_task_enq_ms_i);
                if ((ms_count_i - ev_task_enq_ms_i) > safety_lat_max_ms)
                    safety_lat_max_ms <= ms_count_i - ev_task_enq_ms_i;
            end
            if (ev_ai_start_i)
                ai_task_count <= ai_task_count + 32'd1;
            if (emergency_event_i)
                emergency_event_count <= emergency_event_count + 32'd1;
            if (fifo_count_i > fifo_max_occupancy)
                fifo_max_occupancy <= fifo_count_i;
        end
    end

    // Average latency (combinational integer divide)
    wire [31:0] safety_lat_avg_ms =
        (safety_lat_samples == 32'd0) ? 32'd0 :
        (safety_lat_sum_ms / safety_lat_samples);

    // -------------------------------------------------------------------------
    // Telemetry TX serializer
    // -------------------------------------------------------------------------
    // 33-byte frame: SOF(1)+TYPE(1)+LEN(1)+DATA(28)+CRC(1) = 32 bytes
    // DATA: 7 x uint32 big-endian = 28 bytes
    // -------------------------------------------------------------------------
    localparam TX_BUF_LEN = 33;
    reg [7:0]  tx_buf [0:TX_BUF_LEN-1];
    reg [5:0]  tx_idx;          // 0..32
    reg        tx_sending;

    // Periodic telemetry timer
    reg [31:0] telem_timer;

    // Trigger: READ_METRICS request OR periodic timer
    wire do_send = rd_metrics_req_i ||
                   (ms_tick_i && telem_timer == 32'd0 && !tx_sending);

    integer j;
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            tx_sending   <= 1'b0;
            tx_idx       <= 6'd0;
            tx_valid_o   <= 1'b0;
            tx_byte_o    <= 8'd0;
            telem_timer  <= `TELEM_PERIOD_MS_DEF;
            for (j = 0; j < TX_BUF_LEN; j = j + 1)
                tx_buf[j] <= 8'd0;
        end else begin
            tx_valid_o <= 1'b0;

            // Periodic timer
            if (ms_tick_i) begin
                if (telem_timer == 32'd0)
                    telem_timer <= cfg_telem_period_o;
                else
                    telem_timer <= telem_timer - 32'd1;
            end

            if (!tx_sending && do_send) begin
                // Build telemetry frame into tx_buf
                tx_buf[0]  <= `FRAME_SOF;
                tx_buf[1]  <= 8'h20;     // TYPE: telemetry response
                tx_buf[2]  <= 8'd28;     // LEN: 28 bytes payload

                // safety_task_count [31:0]
                tx_buf[3]  <= safety_task_count[31:24];
                tx_buf[4]  <= safety_task_count[23:16];
                tx_buf[5]  <= safety_task_count[15:8];
                tx_buf[6]  <= safety_task_count[7:0];

                // ai_task_count
                tx_buf[7]  <= ai_task_count[31:24];
                tx_buf[8]  <= ai_task_count[23:16];
                tx_buf[9]  <= ai_task_count[15:8];
                tx_buf[10] <= ai_task_count[7:0];

                // safety_lat_max_ms
                tx_buf[11] <= safety_lat_max_ms[31:24];
                tx_buf[12] <= safety_lat_max_ms[23:16];
                tx_buf[13] <= safety_lat_max_ms[15:8];
                tx_buf[14] <= safety_lat_max_ms[7:0];

                // safety_lat_avg_ms
                tx_buf[15] <= safety_lat_avg_ms[31:24];
                tx_buf[16] <= safety_lat_avg_ms[23:16];
                tx_buf[17] <= safety_lat_avg_ms[15:8];
                tx_buf[18] <= safety_lat_avg_ms[7:0];

                // fifo_max_occupancy
                tx_buf[19] <= 8'd0;
                tx_buf[20] <= 8'd0;
                tx_buf[21] <= 8'd0;
                tx_buf[22] <= {5'd0, fifo_max_occupancy};

                // wdg_event_count
                tx_buf[23] <= 8'd0;
                tx_buf[24] <= 8'd0;
                tx_buf[25] <= wdg_event_count_i[15:8];
                tx_buf[26] <= wdg_event_count_i[7:0];

                // emergency_event_count
                tx_buf[27] <= emergency_event_count[31:24];
                tx_buf[28] <= emergency_event_count[23:16];
                tx_buf[29] <= emergency_event_count[15:8];
                tx_buf[30] <= emergency_event_count[7:0];

                // CRC stub
                tx_buf[31] <= 8'h00;

                tx_idx     <= 6'd0;
                tx_sending <= 1'b1;
            end

            if (tx_sending) begin
                if (tx_ready_i && !tx_valid_o) begin
                    tx_byte_o  <= tx_buf[tx_idx];
                    tx_valid_o <= 1'b1;
                    if (tx_idx == TX_BUF_LEN - 1) begin
                        tx_sending <= 1'b0;
                    end else begin
                        tx_idx <= tx_idx + 6'd1;
                    end
                end
            end
        end
    end

endmodule
