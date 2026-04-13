// =============================================================================
// FILE: frame_parser.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Person A
// =============================================================================
//
// PURPOSE:
//   Binary frame parser FSM. Consumes bytes from uart_rx and assembles
//   complete protocol frames. On a valid frame emits either:
//     - A task_desc_t for the FIFO (SAFETY / AI_TASK / AI_HB)
//     - A metrics request or SET_PARAM command (directly to metrics.v)
//
// FRAME FORMAT: [0xA5][TYPE][LEN][PAYLOAD 0..N][CRC8=0x00 stub]
//
// FSM STATES:
//   WAIT_SOF(0) → RECV_TYPE(1) → RECV_LEN(2) → RECV_PAYLOAD(3) → EMIT(4)
//
// PARAMETERS TO IMPLEMENT:
//   MAX_PAYLOAD = 8  (bytes; reject frames with LEN > this)
//   CRC_ENABLE  = 0  (stub: always pass for MVP)
//
// INTERFACE CONTRACT (outputs to frame_parser):
//   enq_valid_o / enq_task_o / enq_ready_i  → task_fifo
//   ai_heartbeat_o                           → watchdog
//   rd_metrics_req_o                         → metrics
//   set_param_valid_o / _id_o / _val_o       → metrics
//   frame_err_o                              → debug LED
//
// VERIFICATION CHECKLIST:
//   [ ] Valid SAFETY frame → correct task fields.
//   [ ] Valid AI_TASK frame → correct work_cycles.
//   [ ] Unknown TYPE → frame_err, return to WAIT_SOF.
//   [ ] LEN > MAX_PAYLOAD → frame_err, return to WAIT_SOF.
//   [ ] Back-pressure (enq_ready=0) → enq_valid held.
//   [ ] Back-to-back frames both emitted.
//   [ ] ai_heartbeat_o pulses on TYPE_AI_HB.
//   [ ] rd_metrics_req_o pulses on TYPE_RD_MET.
//   [ ] set_param_* correct on TYPE_SET_PAR.
// =============================================================================

`timescale 1ns/1ps
`include "qos_defines.v"

module frame_parser (
    input  wire        clk_i,
    input  wire        rst_ni,

    // From uart_rx
    input  wire [7:0]  rx_byte_i,
    input  wire        rx_valid_i,

    // To task_fifo
    input  wire        enq_ready_i,
    output reg         enq_valid_o,
    output reg  [`TASK_W-1:0] enq_task_o,

    // Timestamp
    input  wire [31:0] ms_count_i,

    // To watchdog
    output reg         ai_heartbeat_o,

    // To metrics
    output reg         rd_metrics_req_o,
    output reg         set_param_valid_o,
    output reg  [7:0]  set_param_id_o,
    output reg  [31:0] set_param_val_o,

    // Debug
    output reg         frame_err_o
);

    localparam MAX_PAYLOAD = 8;

    // FSM states
    localparam WAIT_SOF     = 3'd0;
    localparam RECV_TYPE    = 3'd1;
    localparam RECV_LEN     = 3'd2;
    localparam RECV_PAYLOAD = 3'd3;
    localparam RECV_CRC     = 3'd4;
    localparam EMIT         = 3'd5;

    reg [2:0]  state;
    reg [7:0]  r_type;
    reg [7:0]  r_len;
    reg [7:0]  payload_buf [0:MAX_PAYLOAD-1];
    reg [3:0]  byte_cnt;
    reg [31:0] r_enq_time;

    // Pack helpers
    wire [15:0] w_dist  = {payload_buf[0], payload_buf[1]};
    wire [15:0] w_speed = {payload_buf[2], payload_buf[3]};
    wire [15:0] w_work  = {payload_buf[0], payload_buf[1]};
    wire [7:0]  w_pid   = payload_buf[0];
    wire [31:0] w_val   = {payload_buf[1], payload_buf[2],
                           payload_buf[3], payload_buf[4]};

    integer i;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            state           <= WAIT_SOF;
            enq_valid_o     <= 1'b0;
            enq_task_o      <= {`TASK_W{1'b0}};
            ai_heartbeat_o  <= 1'b0;
            rd_metrics_req_o <= 1'b0;
            set_param_valid_o <= 1'b0;
            set_param_id_o  <= 8'd0;
            set_param_val_o <= 32'd0;
            frame_err_o     <= 1'b0;
            r_type          <= 8'd0;
            r_len           <= 8'd0;
            byte_cnt        <= 4'd0;
            r_enq_time      <= 32'd0;
            for (i = 0; i < MAX_PAYLOAD; i = i + 1)
                payload_buf[i] <= 8'd0;
        end else begin
            // Deassert strobes by default
            ai_heartbeat_o   <= 1'b0;
            rd_metrics_req_o <= 1'b0;
            set_param_valid_o <= 1'b0;
            frame_err_o      <= 1'b0;

            case (state)
                // ----------------------------------------------------------
                WAIT_SOF: begin
                    enq_valid_o <= 1'b0;
                    if (rx_valid_i && rx_byte_i == `FRAME_SOF)
                        state <= RECV_TYPE;
                end

                // ----------------------------------------------------------
                RECV_TYPE: begin
                    if (rx_valid_i) begin
                        // Validate known types
                        if (rx_byte_i == `TYPE_SAFETY  ||
                            rx_byte_i == `TYPE_AI_HB   ||
                            rx_byte_i == `TYPE_AI_TASK  ||
                            rx_byte_i == `TYPE_RD_MET  ||
                            rx_byte_i == `TYPE_SET_PAR) begin
                            r_type      <= rx_byte_i;
                            r_enq_time  <= ms_count_i;
                            state       <= RECV_LEN;
                        end else begin
                            frame_err_o <= 1'b1;
                            state       <= WAIT_SOF;
                        end
                    end
                end

                // ----------------------------------------------------------
                RECV_LEN: begin
                    if (rx_valid_i) begin
                        if (rx_byte_i > MAX_PAYLOAD) begin
                            frame_err_o <= 1'b1;
                            state       <= WAIT_SOF;
                        end else begin
                            r_len    <= rx_byte_i;
                            byte_cnt <= 4'd0;
                            state    <= (rx_byte_i == 8'd0) ? RECV_CRC
                                                             : RECV_PAYLOAD;
                        end
                    end
                end

                // ----------------------------------------------------------
                RECV_PAYLOAD: begin
                    if (rx_valid_i) begin
                        payload_buf[byte_cnt] <= rx_byte_i;
                        if (byte_cnt == (r_len - 4'd1))
                            state <= RECV_CRC;
                        else
                            byte_cnt <= byte_cnt + 4'd1;
                    end
                end

                // ----------------------------------------------------------
                RECV_CRC: begin
                    // CRC stub: consume the byte, always pass
                    if (rx_valid_i) begin
                        state <= EMIT;
                        // Dispatch non-FIFO commands immediately
                        case (r_type)
                            `TYPE_AI_HB: begin
                                ai_heartbeat_o <= 1'b1;
                                state          <= WAIT_SOF;
                            end
                            `TYPE_RD_MET: begin
                                rd_metrics_req_o <= 1'b1;
                                state            <= WAIT_SOF;
                            end
                            `TYPE_SET_PAR: begin
                                set_param_valid_o <= 1'b1;
                                set_param_id_o    <= w_pid;
                                set_param_val_o   <= w_val;
                                state             <= WAIT_SOF;
                            end
                            default: begin
                                // SAFETY and AI_TASK go to FIFO via EMIT
                                // Build task descriptor flat vector
                                enq_task_o[`TASK_TYPE_HI:`TASK_TYPE_LO] <= r_type;
                                enq_task_o[`TASK_ENQ_HI:`TASK_ENQ_LO]   <= r_enq_time;
                                enq_task_o[`TASK_P1_HI:`TASK_P1_LO]     <= 32'd0;
                                if (r_type == `TYPE_SAFETY)
                                    enq_task_o[`TASK_P0_HI:`TASK_P0_LO] <=
                                        {w_dist, w_speed};
                                else  // AI_TASK
                                    enq_task_o[`TASK_P0_HI:`TASK_P0_LO] <=
                                        {16'd0, w_work};
                                enq_valid_o <= 1'b1;
                                state       <= EMIT;
                            end
                        endcase
                    end
                end

                // ----------------------------------------------------------
                EMIT: begin
                    // Hold enq_valid until FIFO accepts
                    if (enq_ready_i) begin
                        enq_valid_o <= 1'b0;
                        state       <= WAIT_SOF;
                    end
                end

                default: state <= WAIT_SOF;
            endcase
        end
    end

endmodule
