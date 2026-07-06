// RV32I opcodes, ALU op encodings, control selects.
`ifndef RISCV_PKG_SV
`define RISCV_PKG_SV
package riscv_pkg;

  localparam logic [6:0] OP_LUI    = 7'b0110111;
  localparam logic [6:0] OP_AUIPC  = 7'b0010111;
  localparam logic [6:0] OP_JAL    = 7'b1101111;
  localparam logic [6:0] OP_JALR   = 7'b1100111;
  localparam logic [6:0] OP_BRANCH = 7'b1100011;
  localparam logic [6:0] OP_LOAD   = 7'b0000011;
  localparam logic [6:0] OP_STORE  = 7'b0100011;
  localparam logic [6:0] OP_IMM    = 7'b0010011;
  localparam logic [6:0] OP_REG    = 7'b0110011;
  localparam logic [6:0] OP_FENCE  = 7'b0001111;
  localparam logic [6:0] OP_SYSTEM = 7'b1110011;  // ECALL/EBREAK/CSR: NOP

  typedef enum logic [3:0] {
    ALU_ADD, ALU_SUB, ALU_SLL, ALU_SLT, ALU_SLTU,
    ALU_XOR, ALU_SRL, ALU_SRA, ALU_OR,  ALU_AND,
    ALU_PASS_B
  } alu_op_e;

  typedef enum logic [0:0] {ALU_SRC_REG = 1'b0, ALU_SRC_IMM = 1'b1} alu_src_e;

  typedef enum logic [1:0] {WB_ALU = 2'b00, WB_MEM = 2'b01, WB_PC4 = 2'b10} wb_sel_e;

  typedef enum logic [2:0] {
    BR_NONE, BR_BEQ, BR_BNE, BR_BLT, BR_BGE, BR_BLTU, BR_BGEU, BR_JUMP
  } br_op_e;

  typedef enum logic [2:0] {IMM_I, IMM_S, IMM_B, IMM_U, IMM_J, IMM_NONE} imm_sel_e;

endpackage
`endif
