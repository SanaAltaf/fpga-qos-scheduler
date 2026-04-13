// =============================================================================
// FILE: uart_tx.v
// PROJECT: FPGA QoS Scheduler and Safety Watchdog (SPEC-001)
// OWNER: Person A
// =============================================================================
//
// PURPOSE:
//   8N1 UART transmitter at 115200 baud. Serializes a byte on tx_valid_i
//   strobe. tx_ready_o is HIGH when idle and ready for a new byte.
//
// FSM STATES: IDLE(0) → START(1) → DATA(2) → STOP(3)
//
// VERIFICATION CHECKLIST:
//   [ ] Idle line HIGH.
//   [ ] Start bit LOW for exactly CYCLES_PER_BIT.
//   [ ] 8 data bits LSB-first, each CYCLES_PER_BIT wide.
//   [ ] Stop bit HIGH for exactly CYCLES_PER_BIT.
//   [ ] tx_ready_o deasserts during TX, reasserts after stop.
//   [ ] Back-to-back bytes without gaps.
// =============================================================================

`timescale 1ns/1ps
`include "qos_defines.v"

module uart_tx (
    input  wire       clk_i,
    input  wire       rst_ni,
    input  wire [7:0] tx_byte_i,
    input  wire       tx_valid_i,

    output reg        tx_o,
    output reg        tx_ready_o
);

    localparam IDLE  = 2'd0;
    localparam START = 2'd1;
    localparam DATA  = 2'd2;
    localparam STOP  = 2'd3;

    reg [1:0]  state;
    reg [9:0]  baud_cnt;
    reg [2:0]  bit_cnt;
    reg [7:0]  shift_reg;

    always @(posedge clk_i) begin
        if (!rst_ni) begin
            state     <= IDLE;
            tx_o      <= 1'b1;
            tx_ready_o <= 1'b1;
            baud_cnt  <= 10'd0;
            bit_cnt   <= 3'd0;
            shift_reg <= 8'd0;
        end else begin
            case (state)
                IDLE: begin
                    tx_o       <= 1'b1;
                    tx_ready_o <= 1'b1;
                    if (tx_valid_i) begin
                        shift_reg  <= tx_byte_i;
                        tx_ready_o <= 1'b0;
                        tx_o       <= 1'b0;    // start bit
                        baud_cnt   <= `CYCLES_PER_BIT - 1;
                        state      <= START;
                    end
                end

                START: begin
                    if (baud_cnt == 10'd0) begin
                        tx_o     <= shift_reg[0];
                        shift_reg <= {1'b0, shift_reg[7:1]};
                        baud_cnt <= `CYCLES_PER_BIT - 1;
                        bit_cnt  <= 3'd0;
                        state    <= DATA;
                    end else begin
                        baud_cnt <= baud_cnt - 10'd1;
                    end
                end

                DATA: begin
                    if (baud_cnt == 10'd0) begin
                        if (bit_cnt == 3'd7) begin
                            tx_o     <= 1'b1;      // stop bit
                            baud_cnt <= `CYCLES_PER_BIT - 1;
                            state    <= STOP;
                        end else begin
                            bit_cnt  <= bit_cnt + 3'd1;
                            tx_o     <= shift_reg[0];
                            shift_reg <= {1'b0, shift_reg[7:1]};
                            baud_cnt <= `CYCLES_PER_BIT - 1;
                        end
                    end else begin
                        baud_cnt <= baud_cnt - 10'd1;
                    end
                end

                STOP: begin
                    if (baud_cnt == 10'd0) begin
                        state <= IDLE;
                    end else begin
                        baud_cnt <= baud_cnt - 10'd1;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
