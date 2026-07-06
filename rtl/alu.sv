// RV32I ALU.
`default_nettype none
module alu (
    input  wire  [31:0]         a,
    input  wire  [31:0]         b,
    input  riscv_pkg::alu_op_e  op,
    output logic [31:0]         y,
    output logic                zero
);
  import riscv_pkg::*;
  always_comb begin
    unique case (op)
      ALU_ADD : y = a + b;
      ALU_SUB : y = a - b;
      ALU_SLL : y = a << b[4:0];
      ALU_SLT : y = ($signed(a) < $signed(b)) ? 32'd1 : 32'd0;
      ALU_SLTU: y = (a  < b)   ? 32'd1 : 32'd0;
      ALU_XOR : y = a ^ b;
      ALU_SRL : y = a >> b[4:0];
      ALU_SRA : y = $signed(a) >>> b[4:0];
      ALU_OR  : y = a | b;
      ALU_AND : y = a & b;
      ALU_PASS_B: y = b;
      default : y = 32'h0;
    endcase
  end
  assign zero = (y == 32'h0);
endmodule
`default_nettype wire
