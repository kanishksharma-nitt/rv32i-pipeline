// Main decoder: datapath control signals from an instruction (combinational).
`default_nettype none
module control (
    input  wire [31:0]           inst,
    output logic                 reg_write,
    output riscv_pkg::wb_sel_e   wb_sel,
    output logic                 mem_read,
    output logic                 mem_write,
    output riscv_pkg::alu_src_e  alu_src_b,
    output logic                 alu_a_pc,    // 1 = PC (AUIPC), 0 = rs1
    output riscv_pkg::alu_op_e   alu_op,
    output riscv_pkg::imm_sel_e  imm_sel,
    output riscv_pkg::br_op_e    br_op,
    output logic                 is_jalr,
    output logic                 illegal
);
  import riscv_pkg::*;
  wire [6:0] opcode = inst[6:0];
  wire [2:0] f3     = inst[14:12];
  wire       f7b5   = inst[30];     // ADD/SUB, SRL/SRA select

  function automatic alu_op_e dec_alu(input logic is_reg);
    unique case (f3)
      3'b000: dec_alu = alu_op_e'((is_reg && f7b5) ? ALU_SUB : ALU_ADD);
      3'b001: dec_alu = ALU_SLL;
      3'b010: dec_alu = ALU_SLT;
      3'b011: dec_alu = ALU_SLTU;
      3'b100: dec_alu = ALU_XOR;
      3'b101: dec_alu = alu_op_e'(f7b5 ? ALU_SRA : ALU_SRL);
      3'b110: dec_alu = ALU_OR;
      3'b111: dec_alu = ALU_AND;
      default: dec_alu = ALU_ADD;
    endcase
  endfunction

  always_comb begin
    reg_write = 1'b0; wb_sel = WB_ALU; mem_read = 1'b0; mem_write = 1'b0;
    alu_src_b = ALU_SRC_REG; alu_a_pc = 1'b0; alu_op = ALU_ADD;
    imm_sel = IMM_NONE; br_op = BR_NONE; is_jalr = 1'b0; illegal = 1'b0;

    unique case (opcode)
      OP_LUI: begin
        reg_write = 1; imm_sel = IMM_U; alu_src_b = ALU_SRC_IMM;
        alu_op = ALU_PASS_B; wb_sel = WB_ALU;
      end
      OP_AUIPC: begin
        reg_write = 1; imm_sel = IMM_U; alu_src_b = ALU_SRC_IMM;
        alu_a_pc = 1; alu_op = ALU_ADD; wb_sel = WB_ALU;
      end
      OP_JAL: begin
        reg_write = 1; imm_sel = IMM_J; wb_sel = WB_PC4; br_op = BR_JUMP;
      end
      OP_JALR: begin
        reg_write = 1; imm_sel = IMM_I; wb_sel = WB_PC4; br_op = BR_JUMP;
        is_jalr = 1;
      end
      OP_BRANCH: begin
        imm_sel = IMM_B; alu_src_b = ALU_SRC_REG;
        unique case (f3)
          3'b000: br_op = BR_BEQ;
          3'b001: br_op = BR_BNE;
          3'b100: br_op = BR_BLT;
          3'b101: br_op = BR_BGE;
          3'b110: br_op = BR_BLTU;
          3'b111: br_op = BR_BGEU;
          default: illegal = 1;
        endcase
      end
      OP_LOAD: begin
        reg_write = 1; mem_read = 1; wb_sel = WB_MEM;
        imm_sel = IMM_I; alu_src_b = ALU_SRC_IMM; alu_op = ALU_ADD;
      end
      OP_STORE: begin
        mem_write = 1; imm_sel = IMM_S; alu_src_b = ALU_SRC_IMM; alu_op = ALU_ADD;
      end
      OP_IMM: begin
        reg_write = 1; imm_sel = IMM_I; alu_src_b = ALU_SRC_IMM;
        alu_op = dec_alu(1'b0);
      end
      OP_REG: begin
        reg_write = 1; alu_src_b = ALU_SRC_REG; alu_op = dec_alu(1'b1);
      end
      OP_FENCE:  begin end // NOP
      OP_SYSTEM: begin end // ECALL/EBREAK/CSR: NOP
      default:   illegal = 1;
    endcase
  end
endmodule
`default_nettype wire
