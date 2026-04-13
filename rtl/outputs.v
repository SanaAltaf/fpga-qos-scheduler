// =============================================================================
// FILE: outputs.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Person C
// =============================================================================
//
// PURPOSE:
//   Drives all physical FPGA outputs: LEDs, PWM pin, and brake signal.
//   Translates internal signals into visible/measurable hardware outputs.
//
// REAL CAR INTEGRATION:
//   pwm_o  → Connect to ESC signal wire (replaces RC receiver signal)
//             Standard RC ESC: 1ms=full-brake, 1.5ms=neutral, 2ms=full-fwd
//             50 Hz PWM period, duty controls throttle
//             On emergency: output 1ms pulse (full brake) continuously
//
//   If not using ESC:
//   pwm_o  → LED bar / buzzer to indicate braking intensity
//   brake_o → Direct GPIO to relay that cuts motor power (safest for demo)
//
// LED MAPPING (Nexys A7):
//   LD0 = emergency_i  (RED = danger)
//   LD1 = failsafe_i   (YELLOW = watchdog fired)
//   LD2 = sched_state[0]
//   LD3 = sched_state[1]
//   LD4-7 = FIFO occupancy bargraph (0..4 LEDs)
//
// PWM NOTES (MVP):
//   8-bit free-running counter (period = 256 cycles ≈ 2.56 µs at 100 MHz)
//   On emergency: duty forced to 0 (motor stop)
//   Normal: duty driven by pwm_duty_i (from host via SET_PARAM or hardcoded)
//
// VERIFICATION CHECKLIST:
//   [ ] emergency_i → led_o[0]=1, pwm_o=0, brake_o=1.
//   [ ] failsafe_i  → led_o[1]=1.
//   [ ] emergency_event_o is exactly 1 cycle wide on rising edge.
//   [ ] PWM duty matches pwm_duty_i when not in emergency.
//   [ ] LED bargraph correct for fifo_count 0,1,2,3,4.
// =============================================================================

`timescale 1ns/1ps
`include "qos_defines.v"

module outputs (
    input  wire        clk_i,
    input  wire        rst_ni,

    input  wire        emergency_i,
    input  wire        failsafe_i,
    input  wire [1:0]  sched_state_i,
    input  wire [2:0]  fifo_count_i,
    input  wire [7:0]  pwm_duty_i,

    output reg  [7:0]  led_o,
    output reg         pwm_o,
    output reg         brake_o,              // Direct brake GPIO (for relay)
    output reg         emergency_event_o     // 1-cycle pulse on emergency rising edge
);

    // -------------------------------------------------------------------------
    // 8-bit PWM counter
    // -------------------------------------------------------------------------
    reg [7:0] pwm_cnt;
    always @(posedge clk_i) begin
        if (!rst_ni) pwm_cnt <= 8'd0;
        else         pwm_cnt <= pwm_cnt + 8'd1;
    end

    // -------------------------------------------------------------------------
    // Emergency rising-edge detect
    // -------------------------------------------------------------------------
    reg prev_emergency;
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            prev_emergency   <= 1'b0;
            emergency_event_o <= 1'b0;
        end else begin
            prev_emergency    <= emergency_i;
            emergency_event_o <= emergency_i & ~prev_emergency;
        end
    end

    // -------------------------------------------------------------------------
    // PWM and brake outputs
    // -------------------------------------------------------------------------
    always @(posedge clk_i) begin
        if (!rst_ni) begin
            pwm_o   <= 1'b0;
            brake_o <= 1'b0;
        end else begin
            if (emergency_i) begin
                pwm_o   <= 1'b0;   // 0% duty = full brake on ESC
                brake_o <= 1'b1;   // Assert relay
            end else begin
                pwm_o   <= (pwm_cnt < pwm_duty_i) ? 1'b1 : 1'b0;
                brake_o <= 1'b0;
            end
        end
    end

    // -------------------------------------------------------------------------
    // LED outputs (combinational)
    // -------------------------------------------------------------------------
    always @(*) begin
        led_o[0] = emergency_i;
        led_o[1] = failsafe_i;
        led_o[3:2] = sched_state_i;
        // FIFO bargraph: light N LEDs for N tasks queued
        led_o[4] = (fifo_count_i >= 3'd1);
        led_o[5] = (fifo_count_i >= 3'd2);
        led_o[6] = (fifo_count_i >= 3'd3);
        led_o[7] = (fifo_count_i >= 3'd4);
    end

endmodule
