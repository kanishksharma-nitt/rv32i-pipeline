# Legacy toolchain

Standalone C tools that build with any C compiler:

- `assembler.c`: RV32I assembler (`.s` to `$readmemh` hex).
- `iss.c`: RV32I instruction-set simulator with register-file dump.

```bash
gcc -O2 -o assembler assembler.c
gcc -O2 -o iss iss.c
```

The active flow uses the RISC-V GNU toolchain and Spike (see the top-level README).
