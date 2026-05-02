// =============================================================================
// FILE: watchdog.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Diego
// =============================================================================

`timescale 1ns/1ps
`include "qos_defines.v"

module watchdog (
    input  wire        clk_i,
    input  wire        rst_ni,

    input  wire        ms_tick_i,
    input  wire [31:0] ms_count_i,
    input  wire        ai_heartbeat_i,
    input  wire [31:0] wdg_timeout_cfg_i,

    output reg         failsafe_o,
    output reg         wdg_event_o,
    output reg  [15:0] wdg_event_count_o,
    output reg  [31:0] ms_since_last_ai_o
);

    reg        prev_failsafe;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            failsafe_o         <= 1'b0;
            wdg_event_o        <= 1'b0;
            wdg_event_count_o  <= 16'd0;
            ms_since_last_ai_o <= 32'd0;
            prev_failsafe      <= 1'b0;
        end else begin
            wdg_event_o <= 1'b0;  // default deassert

            // Reset counter on heartbeat
            if (ai_heartbeat_i) begin
                ms_since_last_ai_o <= 32'd0;
                failsafe_o         <= 1'b0;
            end else begin
                // Increment counter each ms tick (saturate at max)
                if (ms_tick_i && ms_since_last_ai_o < 32'hFFFF_FFFF)
                    ms_since_last_ai_o <= ms_since_last_ai_o + 32'd1;

                // Assert failsafe when timeout exceeded
                if (ms_since_last_ai_o >= wdg_timeout_cfg_i)
                    failsafe_o <= 1'b1;
            end

            // Rising edge detect → pulse wdg_event_o + increment counter
            prev_failsafe <= failsafe_o;
            if (failsafe_o && !prev_failsafe) begin
                wdg_event_o <= 1'b1;
                if (wdg_event_count_o != 16'hFFFF)
                    wdg_event_count_o <= wdg_event_count_o + 16'd1;
            end
        end
    end

endmodule
