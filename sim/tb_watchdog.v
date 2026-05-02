`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Engineer: Diego Masini
// Description: Test bench for ms_tick only assets a clock and reset signal and measures the output behaviour
// 
//////////////////////////////////////////////////////////////////////////////////

module tb_watchdog;

reg clk, rst;
wire ms_tick;
wire [31:0] ms_count;

reg ai_heartbeat;
reg [31:0] wdg_timeout_cfg;

wire failsafe, wdg_event;
wire [15:0] wdg_event_count;
wire [31:0] ms_since_last_ai;


ms_tick ms1(
        .clk_i(clk),
        .rst_ni(rst),
        .ms_tick_o(ms_tick),
        .ms_count_o(ms_count)
        );
        
watchdog uut(
        .clk_i(clk),
        .rst_ni(rst),
        .ms_tick_i(ms_tick),
        .ms_count_i(ms_count),
        .ai_heartbeat_i(ai_heartbeat),
        .wdg_timeout_cfg_i(wdg_timeout_cfg),
        
        .failsafe_o(failsafe),
        .wdg_event_o(wdg_event),
        .wdg_event_count_o(wdg_event_count),
        .ms_since_last_ai_o(ms_since_last_ai)
        );

always #5 clk = ~clk;   
//100 MHz clock to test long time behaviour


task wait_us_heartbeat;
    input integer wait_time;
    begin
        #(wait_time*1000)
        @(posedge clk);
        ai_heartbeat <= 1;
        #10
        ai_heartbeat <= 0;
    end
endtask

initial begin
    clk = 0;
    rst = 0;
    wdg_timeout_cfg = 16'd10;
    ai_heartbeat = 0;
    #7;
    rst = 1;
    
    wait_us_heartbeat(4500);
    wait_us_heartbeat(7500);
    wait_us_heartbeat(10500);
    wait_us_heartbeat(13500);
    
    wdg_timeout_cfg = 16'd12;
    
    wait_us_heartbeat(4500);
    wait_us_heartbeat(7500);
    wait_us_heartbeat(10500);
    wait_us_heartbeat(13500);

end

endmodule
