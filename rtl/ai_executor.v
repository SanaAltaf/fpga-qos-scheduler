// =============================================================================
// FILE: ai_executor.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Sana
// =============================================================================
//
// =============================================================================

`timescale 1ns/1ps
`include "qos_defines.v"

module ai_executor (
    input  wire        clk_i,
    input  wire        rst_ni,

    input  wire        start_i,
    input  wire [15:0] work_cycles_i,
    input  wire        abort_i,

    output reg         busy_o,
    output reg         done_o,
    output reg         aborted_o
);

    reg [15:0] cnt;
    reg        running;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            cnt       <= 16'd0;
            running   <= 1'b0;
            busy_o    <= 1'b0;
            done_o    <= 1'b0;
            aborted_o <= 1'b0;
        end else begin
            done_o    <= 1'b0;
            aborted_o <= 1'b0;

            // PREEMPTION: abort overrides everything
            if (abort_i && running) begin
                running   <= 1'b0;
                busy_o    <= 1'b0;
                done_o    <= 1'b1;
                aborted_o <= 1'b1;

            // NEW TASK: accept start only when idle
            end else if (start_i && !running) begin
                if (work_cycles_i == 16'd0) begin
                    // Zero-cycle task: complete immediately
                    done_o  <= 1'b1;
                    busy_o  <= 1'b0;
                end else begin
                    cnt     <= work_cycles_i - 16'd1;
                    running <= 1'b1;
                    busy_o  <= 1'b1;
                end

            // COUNTING: decrement until zero
            end else if (running) begin
                if (cnt == 16'd0) begin
                    running <= 1'b0;
                    busy_o  <= 1'b0;
                    done_o  <= 1'b1;
                end else begin
                    cnt <= cnt - 16'd1;
                end
            end
        end
    end

endmodule
