// =============================================================================
// FILE: ms_tick.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Person D
// =============================================================================
//
// PURPOSE:
//   Generates a 1 ms periodic pulse (ms_tick_o) and a free-running 32-bit
//   millisecond counter (ms_count_o). All timeout and latency measurements
//   use this as the time base.
//
// IMPLEMENTATION NOTES:
//   Down-counter loaded with (CYCLES_PER_TICK-1). Asserts ms_tick_o for
//   exactly ONE clock cycle when counter hits 0.
//
// PARAMETERS TO IMPLEMENT:
//   CYCLES_PER_TICK = 100_000  (100 MHz / 1000 Hz)
//
// VERIFICATION CHECKLIST:
//   [ ] First tick arrives in exactly CYCLES_PER_TICK cycles after reset.
//   [ ] ms_count_o increments by 1 each tick.
//   [ ] ms_tick_o asserted for exactly 1 clock cycle.
//   [ ] No off-by-one on counter wrap.
// =============================================================================

`timescale 1ns/1ps
`include "qos_defines.v"

module ms_tick (
    input  wire        clk_i,
    input  wire        rst_ni,
    output reg         ms_tick_o,
    output reg  [31:0] ms_count_o
);

    // 17-bit counter sufficient for 100_000
    reg [16:0] cnt;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            cnt        <= `CYCLES_PER_TICK - 1;
            ms_count_o <= 32'd0;
            ms_tick_o  <= 1'b0;
        end else begin
            ms_tick_o <= 1'b0;
            if (cnt == 17'd0) begin
                cnt        <= `CYCLES_PER_TICK - 1;
                ms_tick_o  <= 1'b1;
                ms_count_o <= ms_count_o + 32'd1;
            end else begin
                cnt <= cnt - 17'd1;
            end
        end
    end

endmodule
