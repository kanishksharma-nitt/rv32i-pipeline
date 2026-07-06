// Core + unified word-addressable memory. A store of an odd value to
// TOHOST_ADDR halts the run (riscv-tests convention). Image loaded from MEMFILE.
`default_nettype none
module riscv_soc #(
    parameter int          MEM_WORDS  = 8192,            // 32 KiB
    parameter logic [31:0] RESET_PC   = 32'h0000_0000,
    parameter logic [31:0] TOHOST_ADDR= 32'h0000_1000,
    parameter string       MEMFILE    = ""
) (
    input  wire        clk,
    input  wire        rst_n,
    output logic       halt,
    output logic [31:0] tohost
);
  localparam int AW = $clog2(MEM_WORDS);

  // core <-> memory
  wire [31:0] imem_addr, imem_rdata;
  wire [31:0] dmem_addr, dmem_wdata, dmem_rdata;
  wire [3:0]  dmem_wstrb;
  wire        dmem_we, dmem_re;

  riscv_core #(.RESET_PC(RESET_PC)) u_core (
    .clk(clk), .rst_n(rst_n),
    .imem_addr(imem_addr), .imem_rdata(imem_rdata),
    .dmem_addr(dmem_addr), .dmem_wdata(dmem_wdata), .dmem_wstrb(dmem_wstrb),
    .dmem_we(dmem_we), .dmem_re(dmem_re), .dmem_rdata(dmem_rdata)
  );

  // unified memory
  logic [31:0] mem [MEM_WORDS];
  initial if (MEMFILE != "") $readmemh(MEMFILE, mem);

  wire [AW-1:0] iword = imem_addr[AW+1:2];
  wire [AW-1:0] dword = dmem_addr[AW+1:2];

  assign imem_rdata = mem[iword];
  assign dmem_rdata = mem[dword];

  // byte-strobe write + tohost capture
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      halt <= 1'b0; tohost <= 32'h0;
    end else if (dmem_we) begin
      if (dmem_addr == TOHOST_ADDR) begin
        tohost <= dmem_wdata;
        if (dmem_wdata[0]) halt <= 1'b1;   // odd value terminates the run
      end else begin
        if (dmem_wstrb[0]) mem[dword][7:0]   <= dmem_wdata[7:0];
        if (dmem_wstrb[1]) mem[dword][15:8]  <= dmem_wdata[15:8];
        if (dmem_wstrb[2]) mem[dword][23:16] <= dmem_wdata[23:16];
        if (dmem_wstrb[3]) mem[dword][31:24] <= dmem_wdata[31:24];
      end
    end
  end
endmodule
`default_nettype wire
