// 5-stage pipelined RV32I core (IF/ID/EX/MEM/WB) with full EX forwarding,
// 1-cycle load-use stall, and a 2-cycle flush on taken branch/jump (resolved
// in EX). Combinational-read instruction/data ports; byte-strobe stores.
`default_nettype none
module riscv_core #(
    parameter logic [31:0] RESET_PC = 32'h0000_0000
) (
    input  wire        clk,
    input  wire        rst_n,
    output wire [31:0] imem_addr,
    input  wire [31:0] imem_rdata,
    output wire [31:0] dmem_addr,
    output wire [31:0] dmem_wdata,
    output wire [3:0]  dmem_wstrb,
    output wire        dmem_we,
    output wire        dmem_re,
    input  wire [31:0] dmem_rdata
);
  import riscv_pkg::*;

  // IF stage
  logic [31:0] pc, pc_next;
  logic        stall_pc, stall_if_id, flush_if_id, flush_id_ex;
  logic        ex_take_branch;
  logic [31:0] ex_target;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)        pc <= RESET_PC;
    else if (!stall_pc) pc <= pc_next;
  end

  always_comb begin
    if (ex_take_branch) pc_next = ex_target;
    else                pc_next = pc + 32'd4;
  end

  assign imem_addr = pc;
  wire [31:0] if_inst = imem_rdata;
  wire [31:0] if_pc4  = pc + 32'd4;

  // IF/ID register
  logic [31:0] ifid_pc, ifid_pc4, ifid_inst;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ifid_pc <= '0; ifid_pc4 <= '0; ifid_inst <= 32'h0000_0013; // NOP
    end else if (flush_if_id) begin
      ifid_pc <= '0; ifid_pc4 <= '0; ifid_inst <= 32'h0000_0013;
    end else if (!stall_if_id) begin
      ifid_pc <= pc; ifid_pc4 <= if_pc4; ifid_inst <= if_inst;
    end
  end

  // ID stage: decode + register read + immediate
  wire [4:0] id_rs1 = ifid_inst[19:15];
  wire [4:0] id_rs2 = ifid_inst[24:20];
  wire [4:0] id_rd  = ifid_inst[11:7];
  wire [2:0] id_f3  = ifid_inst[14:12];

  logic      c_reg_write, c_mem_read, c_mem_write, c_alu_a_pc, c_is_jalr, c_illegal;
  wb_sel_e   c_wb_sel;
  alu_src_e  c_alu_src_b;
  alu_op_e   c_alu_op;
  imm_sel_e  c_imm_sel;
  br_op_e    c_br_op;

  control u_ctrl (
    .inst(ifid_inst), .reg_write(c_reg_write), .wb_sel(c_wb_sel),
    .mem_read(c_mem_read), .mem_write(c_mem_write), .alu_src_b(c_alu_src_b),
    .alu_a_pc(c_alu_a_pc), .alu_op(c_alu_op), .imm_sel(c_imm_sel),
    .br_op(c_br_op), .is_jalr(c_is_jalr), .illegal(c_illegal)
  );

  logic        wb_reg_write;
  logic [4:0]  wb_rd;
  logic [31:0] wb_value;
  wire [31:0]  id_rs1_val, id_rs2_val;
  regfile u_rf (
    .clk(clk), .rst_n(rst_n),
    .ra1(id_rs1), .ra2(id_rs2), .rd1(id_rs1_val), .rd2(id_rs2_val),
    .we(wb_reg_write), .wa(wb_rd), .wd(wb_value)
  );

  wire [31:0] id_imm;
  imm_gen u_imm (.inst(ifid_inst), .sel(c_imm_sel), .imm(id_imm));

  // ID/EX register
  logic [31:0] idex_pc, idex_pc4, idex_rs1v, idex_rs2v, idex_imm;
  logic [4:0]  idex_rs1, idex_rs2, idex_rd;
  logic [2:0]  idex_f3;
  logic        idex_reg_write, idex_mem_read, idex_mem_write, idex_alu_a_pc, idex_is_jalr;
  wb_sel_e     idex_wb_sel;
  alu_src_e    idex_alu_src_b;
  alu_op_e     idex_alu_op;
  br_op_e      idex_br_op;

  task automatic idex_bubble;
    idex_reg_write <= 1'b0; idex_mem_read <= 1'b0; idex_mem_write <= 1'b0;
    idex_br_op <= BR_NONE; idex_is_jalr <= 1'b0;
    idex_wb_sel <= WB_ALU; idex_alu_op <= ALU_ADD; idex_alu_src_b <= ALU_SRC_REG;
    idex_alu_a_pc <= 1'b0;
    idex_rs1 <= 5'd0; idex_rs2 <= 5'd0; idex_rd <= 5'd0;
    idex_rs1v <= '0; idex_rs2v <= '0; idex_imm <= '0;
    idex_pc <= '0; idex_pc4 <= '0; idex_f3 <= 3'd0;
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      idex_bubble();
    end else if (flush_id_ex) begin
      idex_bubble();
    end else begin
      idex_pc        <= ifid_pc;
      idex_pc4       <= ifid_pc4;
      idex_rs1v      <= id_rs1_val;
      idex_rs2v      <= id_rs2_val;
      idex_imm       <= id_imm;
      idex_rs1       <= id_rs1;
      idex_rs2       <= id_rs2;
      idex_rd        <= id_rd;
      idex_f3        <= id_f3;
      idex_reg_write <= c_reg_write;
      idex_mem_read  <= c_mem_read;
      idex_mem_write <= c_mem_write;
      idex_alu_a_pc  <= c_alu_a_pc;
      idex_is_jalr   <= c_is_jalr;
      idex_wb_sel    <= c_wb_sel;
      idex_alu_src_b <= c_alu_src_b;
      idex_alu_op    <= c_alu_op;
      idex_br_op     <= c_br_op;
    end
  end

  // EX stage: forwarding, ALU, branch resolution
  logic [31:0] exmem_alu, exmem_pc4, exmem_rs2v;
  logic [4:0]  exmem_rd;
  logic        exmem_reg_write, exmem_mem_read, exmem_mem_write;
  logic [2:0]  exmem_f3;
  wb_sel_e     exmem_wb_sel;

  logic [1:0] fwd_a, fwd_b;
  forwarding_unit u_fwd (
    .ex_rs1(idex_rs1), .ex_rs2(idex_rs2),
    .mem_reg_write(exmem_reg_write), .mem_rd(exmem_rd),
    .wb_reg_write(wb_reg_write),      .wb_rd(wb_rd),
    .fwd_a(fwd_a), .fwd_b(fwd_b)
  );

  wire [31:0] exmem_fwd_val = (exmem_wb_sel == WB_PC4) ? exmem_pc4 : exmem_alu;

  logic [31:0] fa, fb;
  always_comb begin
    unique case (fwd_a)
      2'b10:   fa = exmem_fwd_val;
      2'b01:   fa = wb_value;
      default: fa = idex_rs1v;
    endcase
    unique case (fwd_b)
      2'b10:   fb = exmem_fwd_val;
      2'b01:   fb = wb_value;
      default: fb = idex_rs2v;
    endcase
  end

  wire [31:0] alu_in_a = idex_alu_a_pc ? idex_pc : fa;
  wire [31:0] alu_in_b = (idex_alu_src_b == ALU_SRC_IMM) ? idex_imm : fb;

  wire [31:0] alu_y;
  wire        alu_zero;
  alu u_alu (.a(alu_in_a), .b(alu_in_b), .op(idex_alu_op), .y(alu_y), .zero(alu_zero));

  logic br_cond;
  always_comb begin
    unique case (idex_br_op)
      BR_BEQ : br_cond = (fa == fb);
      BR_BNE : br_cond = (fa != fb);
      BR_BLT : br_cond = ($signed(fa) <  $signed(fb));
      BR_BGE : br_cond = ($signed(fa) >= $signed(fb));
      BR_BLTU: br_cond = (fa <  fb);
      BR_BGEU: br_cond = (fa >= fb);
      BR_JUMP: br_cond = 1'b1;
      default: br_cond = 1'b0;
    endcase
  end

  assign ex_take_branch = (idex_br_op != BR_NONE) && br_cond;
  assign ex_target = idex_is_jalr ? ((fa + idex_imm) & ~32'h1)  // JALR: rs1+imm, clear bit0
                                  : (idex_pc + idex_imm);

  // EX/MEM register
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      exmem_alu <= '0; exmem_pc4 <= '0; exmem_rs2v <= '0; exmem_rd <= 5'd0;
      exmem_reg_write <= 1'b0; exmem_mem_read <= 1'b0; exmem_mem_write <= 1'b0;
      exmem_f3 <= 3'd0; exmem_wb_sel <= WB_ALU;
    end else begin
      exmem_alu       <= alu_y;
      exmem_pc4       <= idex_pc4;
      exmem_rs2v      <= fb;           // forwarded store data
      exmem_rd        <= idex_rd;
      exmem_reg_write <= idex_reg_write;
      exmem_mem_read  <= idex_mem_read;
      exmem_mem_write <= idex_mem_write;
      exmem_f3        <= idex_f3;
      exmem_wb_sel    <= idex_wb_sel;
    end
  end

  // MEM stage: byte-strobe store alignment + load extension
  assign dmem_addr = exmem_alu;
  assign dmem_re   = exmem_mem_read;
  assign dmem_we   = exmem_mem_write;

  logic [3:0]  st_strb;
  logic [31:0] st_data;
  always_comb begin
    st_strb = 4'b0000;
    st_data = exmem_rs2v;
    unique case (exmem_f3)
      3'b000: begin // SB
        st_strb = 4'b0001 << exmem_alu[1:0];
        st_data = {24'b0, exmem_rs2v[7:0]} << (8*exmem_alu[1:0]);
      end
      3'b001: begin // SH
        st_strb = 4'b0011 << (exmem_alu[1] ? 2 : 0);
        st_data = {16'b0, exmem_rs2v[15:0]} << (exmem_alu[1] ? 16 : 0);
      end
      3'b010: begin // SW
        st_strb = 4'b1111;
        st_data = exmem_rs2v;
      end
      default: ;
    endcase
  end
  assign dmem_wstrb = exmem_mem_write ? st_strb : 4'b0000;
  assign dmem_wdata = st_data;

  logic [31:0] load_data;
  logic [7:0]  lb;
  logic [15:0] lh;
  always_comb begin
    lb = dmem_rdata[8*exmem_alu[1:0] +: 8];
    lh = exmem_alu[1] ? dmem_rdata[31:16] : dmem_rdata[15:0];
    unique case (exmem_f3)
      3'b000:  load_data = {{24{lb[7]}},  lb};  // LB
      3'b001:  load_data = {{16{lh[15]}}, lh};  // LH
      3'b010:  load_data = dmem_rdata;          // LW
      3'b100:  load_data = {24'h0, lb};         // LBU
      3'b101:  load_data = {16'h0, lh};         // LHU
      default: load_data = dmem_rdata;
    endcase
  end

  // MEM/WB register
  logic [31:0] memwb_alu, memwb_load, memwb_pc4;
  logic [4:0]  memwb_rd;
  logic        memwb_reg_write;
  wb_sel_e     memwb_wb_sel;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      memwb_alu <= '0; memwb_load <= '0; memwb_pc4 <= '0; memwb_rd <= 5'd0;
      memwb_reg_write <= 1'b0; memwb_wb_sel <= WB_ALU;
    end else begin
      memwb_alu       <= exmem_alu;
      memwb_load      <= load_data;
      memwb_pc4       <= exmem_pc4;
      memwb_rd        <= exmem_rd;
      memwb_reg_write <= exmem_reg_write;
      memwb_wb_sel    <= exmem_wb_sel;
    end
  end

  // WB stage
  always_comb begin
    unique case (memwb_wb_sel)
      WB_MEM : wb_value = memwb_load;
      WB_PC4 : wb_value = memwb_pc4;
      default: wb_value = memwb_alu;
    endcase
  end
  assign wb_reg_write = memwb_reg_write;
  assign wb_rd        = memwb_rd;

  hazard_unit u_haz (
    .id_rs1(id_rs1), .id_rs2(id_rs2),
    .ex_mem_read(idex_mem_read), .ex_rd(idex_rd),
    .ex_take_branch(ex_take_branch),
    .stall_pc(stall_pc), .stall_if_id(stall_if_id),
    .flush_if_id(flush_if_id), .flush_id_ex(flush_id_ex)
  );

endmodule
`default_nettype wire
