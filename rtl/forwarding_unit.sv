// EX operand forwarding: 00 = register, 10 = EX/MEM result, 01 = MEM/WB.
`default_nettype none
module forwarding_unit (
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,
    input  wire       mem_reg_write,
    input  wire [4:0] mem_rd,
    input  wire       wb_reg_write,
    input  wire [4:0] wb_rd,
    output logic [1:0] fwd_a,
    output logic [1:0] fwd_b
);
  always_comb begin
    if (mem_reg_write && mem_rd != 5'd0 && mem_rd == ex_rs1)      fwd_a = 2'b10;
    else if (wb_reg_write && wb_rd != 5'd0 && wb_rd == ex_rs1)    fwd_a = 2'b01;
    else                                                          fwd_a = 2'b00;
    if (mem_reg_write && mem_rd != 5'd0 && mem_rd == ex_rs2)      fwd_b = 2'b10;
    else if (wb_reg_write && wb_rd != 5'd0 && wb_rd == ex_rs2)    fwd_b = 2'b01;
    else                                                          fwd_b = 2'b00;
  end
endmodule
`default_nettype wire
