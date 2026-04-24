// =============================================================================
// FILE: safety_engine.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Person C
// =============================================================================
//
// PURPOSE:
//   Deterministic emergency stop decision. Computes whether distance <= threshold
//   where threshold = STOP_DIST_CM + speed_cm_s/10. Uses a 2-stage pipeline
//   with multiply-then-shift approximation (no divider required).
//
// FORMULA:
//   react_add ≈ (speed_cm_s * 205) >> 11   [error < 0.1%, no divider needed]
//   threshold  = stop_dist_cfg + react_add
//   emergency  = (distance_cm <= threshold)
//
// PIPELINE LATENCY: 2 clock cycles after start_i → done_o asserts.
//
// REAL CAR INTEGRATION NOTE:
//   If attached to a real vehicle:
//     - distance_cm comes from ultrasonic sensor / LiDAR (via UART sensor frame)
//     - speed_cm_s comes from wheel encoder / IMU (via UART sensor frame)
//     - emergency_o drives the physical brake relay / PWM via outputs.v
//     - STOP_DIST_CM tunable at runtime via SET_PARAM from host laptop
//
// VERIFICATION CHECKLIST:
//   [ ] dist=30, spd=0,   stop=50 → emergency (30<=50).
//   [ ] dist=60, spd=0,   stop=50 → no emergency.
//   [ ] dist=60, spd=100, stop=50 → emergency (60<=60).
//   [ ] dist=62, spd=100, stop=50 → no emergency.
//   [ ] done_o asserts exactly 2 cycles after start_i.
//   [ ] emergency_o latches until next start_i.
// =============================================================================

`timescale 1ns/1ps
`include "qos_defines.v"

module safety_engine (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Dispatch from scheduler
    input  wire        start_i,
    input  wire [`DIST_W-1:0] distance_cm_i,
    input  wire [`SPEED_W-1:0] speed_cm_s_i,

    // Runtime config (from metrics.v config regs)
    input  wire [15:0] stop_dist_cfg_i,

    // Result
    output reg         done_o,
    output reg         emergency_o
);

    // -------------------------------------------------------------------------
    // Stage 1: Multiply speed * 205 (approximates /10 after >>11)
    // -------------------------------------------------------------------------
    reg [31:0] s1_mul;         // speed_cm_s * 205 (32-bit)
    reg [15:0] s1_dist;        // registered distance
    reg [15:0] s1_stop;        // registered stop_dist
    reg        s1_valid;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            s1_mul   <= 32'd0;
            s1_dist  <= 16'd0;
            s1_stop  <= 16'd0;
            s1_valid <= 1'b0;
        end else begin
            s1_valid <= start_i;
            if (start_i) begin
                s1_mul  <= speed_cm_s_i * 16'd205;
                s1_dist <= distance_cm_i;
                s1_stop <= stop_dist_cfg_i;
            end
        end
    end

    // -------------------------------------------------------------------------
    // Stage 2: Shift >>11, add stop_dist, compare
    // react_add = s1_mul[26:11]  (equivalent to >> 11, upper 16 bits)
    // -------------------------------------------------------------------------
    wire [15:0] react_add  = s1_mul >> 11;
    wire [16:0] threshold  = {1'b0, s1_stop} + {1'b0, react_add}; // 17-bit to avoid overflow

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            done_o      <= 1'b0;
            emergency_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (s1_valid) begin
                done_o      <= 1'b1;
                // Emergency if distance <= threshold (clamp threshold at 0xFFFF)
                emergency_o <= (s1_dist <= threshold[15:0]) ||
                               (threshold[16] == 1'b1);  // overflow → huge threshold → no emerg
                                                          // Actually if overflow, threshold>dist always
                                                          // Correct: if threshold overflows 16-bit,
                                                          // distance can never exceed it
            end
        end
    end

endmodule
