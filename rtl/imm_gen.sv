// Sign-extended immediate generation for all RV32I formats.
`default_nettype none
module imm_gen (
    input  wire [31:0]          inst,
    input  riscv_pkg::imm_sel_e sel,
    output logic [31:0]         imm
);
  import riscv_pkg::*;
  always_comb begin
    unique case (sel)
      IMM_I: imm = {{20{inst[31]}}, inst[31:20]};
      IMM_S: imm = {{20{inst[31]}}, inst[31:25], inst[11:7]};
      IMM_B: imm = {{19{inst[31]}}, inst[31], inst[7], inst[30:25], inst[11:8], 1'b0};
      IMM_U: imm = {inst[31:12], 12'h0};
      IMM_J: imm = {{11{inst[31]}}, inst[31], inst[19:12], inst[20], inst[30:21], 1'b0};
      default: imm = 32'h0;
    endcase
  end
endmodule
`default_nettype wire
