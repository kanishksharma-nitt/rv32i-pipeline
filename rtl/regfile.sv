// 32x32 register file: x0 tied to 0, write-first bypass (WB visible to same-cycle ID).
`default_nettype none
module regfile (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [4:0]  ra1,
    input  wire [4:0]  ra2,
    output wire [31:0] rd1,
    output wire [31:0] rd2,
    input  wire        we,
    input  wire [4:0]  wa,
    input  wire [31:0] wd
);
  logic [31:0] regs [32];

  integer i;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < 32; i = i + 1) regs[i] <= 32'h0;
    end else if (we && wa != 5'd0) begin
      regs[wa] <= wd;
    end
  end

  assign rd1 = (ra1 == 5'd0)              ? 32'h0 :
               (we && wa == ra1)          ? wd    : regs[ra1];
  assign rd2 = (ra2 == 5'd0)              ? 32'h0 :
               (we && wa == ra2)          ? wd    : regs[ra2];
endmodule
`default_nettype wire
