module tb_safety_engine();
 reg clk_i;
 reg rst_ni;
 reg start_i;
 reg [`DIST_W-1:0]   distance_cm_i;
 reg [`SPEED_W-1:0]  speed_cm_s_i;
 reg [15:0]          stop_dist_cfg_i;
 
 wire                done_o;
 wire                emergency_o;
 
 safety_engine DUT ( .clk_i(clk_i),
                     .rst_ni(rst_ni),
                     .start_i(start_i),
                     .distance_cm_i(distance_cm_i),
                     .speed_cm_s_i(speed_cm_s_i),
                     .stop_dist_cfg_i(stop_dist_cfg_i),
                     .done_o(done_o),
                     .emergency_o(emergency_o)
                   );
                   
  initial
  begin
   clk_i =1'b0;
  end
  always #5 clk_i = ~ clk_i;
  task run_case;
    input [`DIST_W-1:0] dist;
    input [`SPEED_W-1:0] speed;
    input [15: 0] stop_dist;
    begin 
      @(negedge clk_i);
      distance_cm_i = dist;
      speed_cm_s_i = speed;
      stop_dist_cfg_i = stop_dist;
      start_i = 1'b1;
  
      @(negedge clk_i);
      start_i = 1'b0;
     
   end
  endtask
  
  initial begin
     rst_ni =1'b0; 
     start_i = 1'b0; 
     distance_cm_i = {`DIST_W{1'b0}}; 
     speed_cm_s_i = {`SPEED_W{1'b0}};
     stop_dist_cfg_i= `STOP_DIST_CM_DEFAULT; 
     #20;
  
     rst_ni =1'b1;
  
  //Test case 
  
     run_case(16'd30, 16'd0, 16'd50);         // 30<= 50
     run_case(16'd60, 16'd0, 16'd50);          //60<=50
     run_case(16'd60, 16'd100, 16'd50);         //60<=60
     run_case(16'd30, 16'd500, 16'd50);        //30<=100
     #20;
     $finish;
    end 
                    
endmodule
