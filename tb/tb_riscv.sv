// Self-checking testbench for the RV32I pipeline.
// Plusargs: +MEMFILE=<hex> (required), +MAXCYC=<n>, +DUMP=<file>, +TRACE.
// Pass/fail via the riscv-tests tohost convention (store 1 = PASS).
`default_nettype none
`timescale 1ns/1ps
module tb_riscv;
  logic clk = 0, rst_n = 0;
  logic        halt;
  logic [31:0] tohost;

  string memfile, dumpfile;
  int    maxcyc;
  int    cyc = 0;

  initial clk = 0;
  always #5 clk = ~clk;

  // Base 0x8000_0000, tohost 0x8000_1000 (matches the linker script and Spike).
  riscv_soc #(.MEM_WORDS(8192),
              .RESET_PC(32'h8000_0000),
              .TOHOST_ADDR(32'h8000_1000)) dut (
    .clk(clk), .rst_n(rst_n), .halt(halt), .tohost(tohost)
  );

  initial begin
    if (!$value$plusargs("MEMFILE=%s", memfile)) begin
      $display("FATAL: +MEMFILE=<hex> required"); $finish;
    end
    $readmemh(memfile, dut.mem);
    if (!$value$plusargs("MAXCYC=%d", maxcyc)) maxcyc = 100000;
  end

  initial begin
    rst_n = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;
  end

  // cycle counter / timeout
  always_ff @(posedge clk) begin
    if (rst_n) begin
      cyc <= cyc + 1;
      if (cyc > maxcyc) begin
        $display("\n*** TIMEOUT after %0d cycles ***", cyc);
        $display("TEST FAILED");
        finish_dump(); $finish;
      end
    end
  end

  initial begin
    if ($test$plusargs("TRACE")) begin
      forever begin
        @(posedge clk);
        if (rst_n && dut.u_core.memwb_reg_write && dut.u_core.memwb_rd != 0)
          $display("[%0t] WB x%0d <= 0x%08h", $time,
                   dut.u_core.memwb_rd, dut.u_core.wb_value);
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst_n && halt) begin
      $display("\n=== Simulation finished at cycle %0d ===", cyc);
      $display("tohost = 0x%08h", tohost);
      if (tohost == 32'h1)
        $display("TEST PASSED");
      else
        $display("TEST FAILED (failing test #%0d)", tohost >> 1);
      finish_dump();
      $finish;
    end
  end

  task finish_dump;
    integer fd, i;
    if ($value$plusargs("DUMP=%s", dumpfile)) begin
      fd = $fopen(dumpfile, "w");
      for (i = 0; i < 32; i = i + 1)
        $fwrite(fd, "x%0d %08x\n", i, dut.u_core.u_rf.regs[i]);
      $fclose(fd);
    end
  endtask

  initial begin
    $dumpfile("tb_riscv.vcd");
    $dumpvars(0, tb_riscv);
  end
endmodule
`default_nettype wire
