# Targets: hex, build, all, run TEST=x, equiv, golden, lint, clean.
# Needs: iverilog, verilator, riscv64-unknown-elf-gcc, spike, python3.
TOP        = tb_riscv
VVP        = sim.vvp
HEXDIR     = ../tests/hex
ASMDIR     = ../tests/asm
LDSCRIPT   = ../tests/link.ld
TEST      ?= test_arith
MAXCYC    ?= 200000

RISCV_PREFIX ?= riscv64-unknown-elf-
RISCV_GCC     = $(RISCV_PREFIX)gcc
RISCV_OBJCOPY = $(RISCV_PREFIX)objcopy
GCC_FLAGS     = -march=rv32i -mabi=ilp32 -nostdlib -nostartfiles -Wl,-T,$(LDSCRIPT)

SPIKE   ?= spike
SPIKE_ISA ?= rv32i
PYTHON  ?= python3
COMPARE  = $(PYTHON) ../scripts/compare_regs.py

check-gnu:
	@command -v $(RISCV_GCC) >/dev/null 2>&1 || { \
	  echo "ERROR: $(RISCV_GCC) not found (RISC-V GNU toolchain)."; \
	  echo "  Ubuntu/Debian:  sudo apt-get install gcc-riscv64-unknown-elf"; \
	  echo "  macOS (brew):   brew tap riscv-software-src/riscv && brew install riscv-gnu-toolchain"; \
	  exit 1; }

check-spike:
	@command -v $(SPIKE) >/dev/null 2>&1 || { \
	  echo "ERROR: spike (riscv-isa-sim) not found."; \
	  echo "  Build:  git clone https://github.com/riscv-software-src/riscv-isa-sim"; \
	  echo "          cd riscv-isa-sim && mkdir build && cd build && ../configure && make && sudo make install"; \
	  echo "  macOS (brew):  brew install riscv-isa-sim"; \
	  exit 1; }

build:
	iverilog -g2012 -Wall -s $(TOP) -o $(VVP) -f files.f

# .s -> .elf -> .bin -> word-per-line hex. The ELF is kept for Spike (equiv).
hex: check-gnu
	@mkdir -p $(HEXDIR)
	@for s in $(ASMDIR)/*.s; do \
	   n=$$(basename $$s .s); \
	   $(RISCV_GCC) $(GCC_FLAGS) $$s -o $(HEXDIR)/$$n.elf && \
	   $(RISCV_OBJCOPY) -O binary --only-section=.text $(HEXDIR)/$$n.elf $(HEXDIR)/$$n.bin && \
	   od -An -tx4 -w4 -v $(HEXDIR)/$$n.bin | sed 's/^ *//' > $(HEXDIR)/$$n.hex; \
	 done
	@echo "assembled $$(ls $(ASMDIR)/*.s | wc -l) programs (RISC-V GNU toolchain)"

run: build
	vvp $(VVP) +MEMFILE=$(HEXDIR)/$(TEST).hex +MAXCYC=$(MAXCYC) +DUMP=$(TEST).dump

all: build hex
	@pass=0; fail=0; \
	for h in $(HEXDIR)/*.hex; do \
	   n=$$(basename $$h .hex); \
	   out=$$(vvp $(VVP) +MEMFILE=$$h +MAXCYC=$(MAXCYC)); \
	   if echo "$$out" | grep -q "TEST PASSED"; then \
	     echo "PASS  $$n"; pass=$$((pass+1)); \
	   else \
	     echo "FAIL  $$n"; echo "$$out" | tail -3; fail=$$((fail+1)); \
	   fi; \
	 done; \
	 echo "-----------------------------"; \
	 echo "passed=$$pass failed=$$fail"; \
	 test $$fail -eq 0

# Lockstep: RTL register file vs the file rebuilt from Spike's commit log.
equiv: build hex check-spike
	@rc=0; \
	for e in $(HEXDIR)/*.elf; do \
	   n=$$(basename $$e .elf); \
	   vvp $(VVP) +MEMFILE=$(HEXDIR)/$$n.hex +MAXCYC=$(MAXCYC) +DUMP=$$n.rtl.dump >/dev/null; \
	   $(SPIKE) --isa=$(SPIKE_ISA) --log-commits -l $$e 2>$$n.spike.log >/dev/null; \
	   if $(COMPARE) --spike-log $$n.spike.log --rtl $$n.rtl.dump; then \
	     echo "EQUIV PASS  $$n"; \
	   else \
	     echo "EQUIV FAIL  $$n"; rc=1; \
	   fi; \
	 done; \
	 exit $$rc

golden: hex check-spike
	@mkdir -p ../tests/golden
	@for e in $(HEXDIR)/*.elf; do \
	   n=$$(basename $$e .elf); \
	   $(SPIKE) --isa=$(SPIKE_ISA) --log-commits -l $$e 2>$$n.spike.log >/dev/null; \
	   $(COMPARE) --spike-log $$n.spike.log --emit ../tests/golden/$$n.dump; \
	 done
	@echo "regenerated golden dumps from Spike"

lint:
	verilator --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL \
	  -Wno-UNUSEDPARAM --top-module riscv_soc \
	  ../rtl/riscv_pkg.sv ../rtl/regfile.sv ../rtl/alu.sv ../rtl/imm_gen.sv \
	  ../rtl/control.sv ../rtl/hazard_unit.sv ../rtl/forwarding_unit.sv \
	  ../rtl/riscv_core.sv ../rtl/riscv_soc.sv

clean:
	rm -f $(VVP) *.vcd *.dump *.spike.log
	rm -f $(HEXDIR)/*.elf $(HEXDIR)/*.bin
