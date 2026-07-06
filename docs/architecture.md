# RV32I core architecture

## Pipeline stages

| Stage | Work done |
|-------|-----------|
| IF    | Drive PC to instruction memory; compute PC+4. |
| ID    | Decode (`control.sv`), read register file, generate immediate (`imm_gen.sv`). |
| EX    | Forward operands, ALU compute, resolve branch condition + target. |
| MEM   | Data-memory load/store with byte strobes; sign/zero-extend loads. |
| WB    | Select writeback value (ALU / load / PC+4) and write the register file. |

## Control signals (per instruction class)

| Class  | reg_write | wb_sel | mem | alu_src_b | alu_op    | br_op  |
|--------|:---------:|:------:|:---:|:---------:|-----------|--------|
| LUI    | 1 | ALU | -   | imm | PASS_B | none |
| AUIPC  | 1 | ALU | -   | imm | ADD (a=PC) | none |
| JAL    | 1 | PC4 | -   | -   | -      | jump |
| JALR   | 1 | PC4 | -   | imm | -      | jump (rs1+imm) |
| BRANCH | 0 | -   | -   | reg | -      | beq…bgeu |
| LOAD   | 1 | MEM | rd  | imm | ADD    | none |
| STORE  | 0 | -   | wr  | imm | ADD    | none |
| OP-IMM | 1 | ALU | -   | imm | funct3 | none |
| OP     | 1 | ALU | -   | reg | funct3/funct7 | none |

## Hazards

- RAW via forwarding: EX operands come from EX/MEM (priority) or MEM/WB.
- Load-use: a 1-cycle stall (bubble in EX) when a load in EX feeds the
  instruction in ID; the load result is then forwarded from MEM/WB.
- Control: branch/jump resolved in EX flushes IF/ID and ID/EX (2-cycle penalty
  when taken).
