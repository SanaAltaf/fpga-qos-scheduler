`timescale 1ns/1ps
module tb_FIFO;

   reg                                    clk_i;
   reg                                    rst_ni;
   reg                                    enq_valid_i;
   reg    [`TASK_W-1:0]                   enq_task_i;
   reg                                    deq_req_i;
   reg    [`FIFO_ADDR_W-1:0]              deq_idx_i;

   wire                                   enq_ready_o;
   wire   [`FIFO_DEPTH-1:0]               peek_valid_o;
   wire   [`TASK_W-1:0]                   peek_task0_o;
   wire   [`TASK_W-1:0]                   peek_task1_o;
   wire   [`TASK_W-1:0]                   peek_task2_o;
   wire   [`TASK_W-1:0]                   peek_task3_o;
   wire   [`FIFO_ADDR_W:0]                count_o;
   wire                                   full_o;
   wire                                   empty_o;

   integer                                expected_count;
   reg                                    accepted;
   reg                                    was_valid;
   

   FIFO DUT (
      .clk_i(clk_i),
      .rst_ni(rst_ni),
      .enq_valid_i(enq_valid_i),
      .enq_task_i(enq_task_i),
      .deq_req_i(deq_req_i),
      .deq_idx_i(deq_idx_i),
      .enq_ready_o(enq_ready_o),
      .peek_valid_o(peek_valid_o),
      .peek_task0_o(peek_task0_o),
      .peek_task1_o(peek_task1_o),
      .peek_task2_o(peek_task2_o),
      .peek_task3_o(peek_task3_o),
      .count_o(count_o),
      .full_o(full_o),
      .empty_o(empty_o)
   );

   initial begin
      clk_i = 1'b0;
   end

   always #5 clk_i = ~clk_i;

   task enqueue_task;
      input [`TASK_W-1:0] task_data;
      begin
         @(negedge clk_i);
         enq_valid_i = 1'b1;
         enq_task_i  = task_data;

         @(negedge clk_i);
         enq_valid_i = 1'b0;
         enq_task_i  = {`TASK_W{1'b0}};
      end
   endtask

   task dequeue_task;
      input [`FIFO_ADDR_W-1:0] slot_idx;
      begin
         @(negedge clk_i);
         deq_req_i = 1'b1;
         deq_idx_i = slot_idx;

         @(negedge clk_i);
         deq_req_i = 1'b0;
         deq_idx_i = {`FIFO_ADDR_W{1'b0}};
      end
   endtask

   task check_count;
      input [`FIFO_ADDR_W:0] exp_count;
      begin
         if (count_o !== exp_count)
            $display("[FAIL] expected count = %0d, actual count = %0d", exp_count, count_o);
         else
            $display("[PASS] expected count = %0d, actual count = %0d", exp_count, count_o);
      end
   endtask
    
    task check_valid;
        input [`FIFO_DEPTH-1:0] exp_valid;
        begin
        if( peek_valid_o !== exp_valid)
            $display("[FAIL] expected value =%b, actual value = %b", exp_valid, peek_valid_o);
        else 
            $display ("[PASS] expected value=%b, actual value =%b", exp_valid,peek_valid_o);
        end
    endtask

   initial begin
      rst_ni           = 1'b0;
      enq_valid_i      = 1'b0;
      enq_task_i       = {`TASK_W{1'b0}};
      deq_req_i        = 1'b0;
      deq_idx_i        = {`FIFO_ADDR_W{1'b0}};
      expected_count   = 0;
      accepted         = 1'b0;
      was_valid        = 1'b0;

      #20;
      rst_ni = 1'b1;
      

      @(negedge clk_i);
      check_count(0);

      if (empty_o !== 1'b1)
         $display("[FAIL] empty_o should be 1 after reset");
      else
         $display("[PASS] empty_o should be 1 after reset");

      if (full_o !== 1'b0)
         $display("[FAIL] full_o should be 0 after reset");
      else
         $display("[PASS] full_o correct after reset");
         
         
      // After Reset
      check_count(0);
      check_valid(4'b0000);

      // 1st enqueue
      accepted = enq_ready_o;
      enqueue_task('h1);
      if (accepted)
         expected_count = expected_count + 1;
      check_count(expected_count);
      check_valid(4'b0001);

      // 2nd enqueue
      accepted = enq_ready_o;
      enqueue_task('h2);
      if (accepted)
         expected_count = expected_count + 1;
      check_count(expected_count);
      check_valid(4'b0011);

      // 3rd enqueue
      accepted = enq_ready_o;
      enqueue_task('h4);
      if (accepted)
         expected_count = expected_count + 1;
      check_count(expected_count);
      check_valid(4'b0111);

      // 4th enqueue
      accepted = enq_ready_o;
      enqueue_task('h8);
      if (accepted)
         expected_count = expected_count + 1;
      check_count(expected_count);
      check_valid(4'b1111);

      // 5th enqueue - overflow test
      accepted = enq_ready_o;
      enqueue_task('h16);
      if (accepted)
         expected_count = expected_count + 1;
      check_count(expected_count);
      check_valid(4'b1111);

      if (full_o !== 1'b1)
         $display("[FAIL] full_o should be 1 when FIFO is full");
      else
         $display("[PASS] full_o asserted when FIFO is full");

      if (enq_ready_o !== 1'b0)
         $display("[FAIL] enq_ready_o should be 0 when FIFO is full");
      else
         $display("[PASS] enq_ready_o deasserted when FIFO is full");

      // dequeue slot 0
      was_valid = peek_valid_o[0];
      dequeue_task(2'b00);
      if (was_valid)
         expected_count = expected_count - 1;
      check_count(expected_count);
      check_valid(4'b1110);
      // dequeue slot 3
      was_valid = peek_valid_o[3];
      dequeue_task(2'b11);
      if (was_valid)
         expected_count = expected_count - 1;
      check_count(expected_count);
      check_valid(4'b0110);  
      
       // dequeue slot 0 again
      was_valid = peek_valid_o[0];
      dequeue_task(2'b00);
      if (was_valid)
         expected_count = expected_count - 1;
      check_count(expected_count);
      check_valid(4'b0110); 
      
      
      // 6th enqueue ( checking the new data enter the lowest slot
      accepted = enq_ready_o;
      enqueue_task('h16);
      if (accepted)
         expected_count = expected_count + 1;
      check_count(expected_count);
      check_valid(4'b0111);
      
      // dequeue slot 1 
      was_valid = peek_valid_o[1];
      dequeue_task(2'b01);
      if (was_valid)
         expected_count = expected_count - 1;
      check_count(expected_count);
      check_valid(4'b0101);
      
     // dequeue slot 2
      was_valid = peek_valid_o[2];
      dequeue_task(2'b10);
      if (was_valid)
         expected_count = expected_count - 1;
      check_count(expected_count);
      check_valid(4'b0001);
      
      // dequeue slot 0
      was_valid = peek_valid_o[0];
      dequeue_task(2'b00);
      if (was_valid)
         expected_count = expected_count - 1;
      check_count(expected_count);
      check_valid(4'b0000);
      
      if (empty_o !== 1'b1)
         $display("[FAIL] empty_o should be 1 when FIFO becomes empty");
      else 
         $display("[PASS] empty_o asserted when FIFO becomes empty");
      
      
      #20;
      $finish;
   end

endmodule
