// =============================================================================
// FILE: safety_engine.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Sana
// =============================================================================
`timescale 1ns/1ps
`include "qos_defines.v"

module safety_engine (
    input  wire        clk_i,
    input  wire        rst_ni,

    // Dispatch from scheduler
    input  wire        start_i,
    input  wire [15:0] distance_cm_i,
    input  wire [15:0] speed_cm_s_i,

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
    wire [15:0] react_add  = s1_mul[26:11];
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
