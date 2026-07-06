// Load-use stall detection + branch flush control.
`default_nettype none
module hazard_unit (
    input  wire [4:0] id_rs1,
    input  wire [4:0] id_rs2,
    input  wire       ex_mem_read,
    input  wire [4:0] ex_rd,
    input  wire       ex_take_branch,
    output wire       stall_pc,
    output wire       stall_if_id,
    output wire       flush_if_id,
    output wire       flush_id_ex
);
  wire load_use = ex_mem_read && (ex_rd != 5'd0) &&
                  ((ex_rd == id_rs1) || (ex_rd == id_rs2));

  // A taken branch flush takes priority over a load-use stall.
  assign stall_pc    = load_use && !ex_take_branch;
  assign stall_if_id = load_use && !ex_take_branch;
  assign flush_id_ex = (load_use && !ex_take_branch) || ex_take_branch;
  assign flush_if_id = ex_take_branch;
endmodule
`default_nettype wire
