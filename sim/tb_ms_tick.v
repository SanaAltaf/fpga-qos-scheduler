`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Diego Masini
// Description: Test bench for ms_tick only assets a clock and reset signal and measures the output behaviour
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_ms_tick;

reg clk, rst;
wire ms_tick;
wire [31:0] ms_count;

ms_tick uut(
        .clk_i(clk),
        .rst_ni(rst),
        .ms_tick_o(ms_tick),
        .ms_count_o(ms_count)
        );

always #5 clk = ~clk;   
//100,000 MHz clock to test long time behaviour

initial begin
    clk = 0;
    rst = 0;
    #7;
    rst = 1;
end
endmodule
