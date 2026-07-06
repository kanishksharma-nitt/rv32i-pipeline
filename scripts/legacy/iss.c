/* RV32I instruction-set simulator.  iss prog.hex [--maxcyc N] [--dump f] [--trace] */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#define MASK    0xFFFFFFFFu
#define TOHOST  0x1000u
#define MEM_WORDS 65536

static uint32_t mem[MEM_WORDS];
static uint32_t regs[32];
static uint32_t tohost_val = 0;
static int halted = 0;

static int32_t sx(uint32_t v, int bits) {
    uint32_t m = (bits >= 32) ? 0xFFFFFFFFu : ((1u << bits) - 1u);
    v &= m;
    uint32_t sign = 1u << (bits - 1);
    return (v & sign) ? (int32_t)(v - (m + 1u)) : (int32_t)v;
}

static uint32_t mem_load_w(uint32_t addr) {
    uint32_t idx = addr >> 2;
    if (idx >= MEM_WORDS) { fprintf(stderr, "mem read out of range: 0x%08x\n", addr); exit(1); }
    return mem[idx];
}

static void mem_store(uint32_t addr, uint32_t data, int strb) {
    if (addr == TOHOST) {
        tohost_val = data & MASK;
        if (data & 1) halted = 1;
        return;
    }
    uint32_t idx = addr >> 2;
    if (idx >= MEM_WORDS) { fprintf(stderr, "mem write out of range: 0x%08x\n", addr); exit(1); }
    uint32_t word = mem[idx];
    int b;
    for (b = 0; b < 4; b++) {
        if (strb & (1 << b)) {
            word &= ~(0xFFu << (8 * b));
            word |= (data & (0xFFu << (8 * b)));
        }
    }
    mem[idx] = word;
}

static uint32_t step(uint32_t pc, int trace) {
    uint32_t inst = mem_load_w(pc);
    uint32_t op = inst & 0x7F;
    uint32_t rd = (inst >> 7) & 0x1F;
    uint32_t f3 = (inst >> 12) & 0x7;
    uint32_t rs1 = (inst >> 15) & 0x1F;
    uint32_t rs2 = (inst >> 20) & 0x1F;
    uint32_t f7 = (inst >> 25) & 0x7F;
    uint32_t a = regs[rs1];
    uint32_t b = regs[rs2];
    uint32_t npc = pc + 4;

    int32_t imm_i = sx(inst >> 20, 12);
    int32_t imm_s = sx(((inst >> 25) << 5) | ((inst >> 7) & 0x1F), 12);
    int32_t imm_b = sx((((inst >> 31) & 1) << 12) | (((inst >> 7) & 1) << 11) |
                       (((inst >> 25) & 0x3F) << 5) | (((inst >> 8) & 0xF) << 1), 13);
    uint32_t imm_u = inst & 0xFFFFF000u;
    int32_t imm_j = sx((((inst >> 31) & 1) << 20) | (((inst >> 12) & 0xFF) << 12) |
                       (((inst >> 20) & 1) << 11) | (((inst >> 21) & 0x3FF) << 1), 21);

    int has_wb = 0;
    uint32_t wb_val = 0;

    if (op == 0x33) {
        uint32_t r;
        if (f3 == 0) r = (f7 == 0x20) ? (a - b) : (a + b);
        else if (f3 == 1) r = a << (b & 0x1F);
        else if (f3 == 2) r = (sx(a, 32) < sx(b, 32)) ? 1 : 0;
        else if (f3 == 3) r = (a < b) ? 1 : 0;
        else if (f3 == 4) r = a ^ b;
        else if (f3 == 5) r = (f7 == 0x20) ? (uint32_t)(sx(a, 32) >> (b & 0x1F)) : (a >> (b & 0x1F));
        else if (f3 == 6) r = a | b;
        else r = a & b;
        has_wb = 1; wb_val = r;
    } else if (op == 0x13) {
        uint32_t sh = (inst >> 20) & 0x1F;
        uint32_t r = 0;
        if (f3 == 0) r = (uint32_t)((int32_t)a + imm_i);
        else if (f3 == 2) r = (sx(a, 32) < imm_i) ? 1 : 0;
        else if (f3 == 3) r = (a < (uint32_t)imm_i) ? 1 : 0;
        else if (f3 == 4) r = a ^ (uint32_t)imm_i;
        else if (f3 == 6) r = a | (uint32_t)imm_i;
        else if (f3 == 7) r = a & (uint32_t)imm_i;
        else if (f3 == 1) r = a << sh;
        else if (f3 == 5) r = (f7 == 0x20) ? (uint32_t)(sx(a, 32) >> sh) : (a >> sh);
        has_wb = 1; wb_val = r;
    } else if (op == 0x03) {
        uint32_t addr = (uint32_t)((int32_t)a + imm_i);
        uint32_t word = mem_load_w(addr & ~3u);
        uint32_t off = addr & 3;
        uint32_t r = 0;
        if (f3 == 0) r = (uint32_t)sx((word >> (8 * off)) & 0xFF, 8);
        else if (f3 == 1) r = (uint32_t)sx((word >> ((addr & 2) ? 16 : 0)) & 0xFFFF, 16);
        else if (f3 == 2) r = word;
        else if (f3 == 4) r = (word >> (8 * off)) & 0xFF;
        else if (f3 == 5) r = (word >> ((addr & 2) ? 16 : 0)) & 0xFFFF;
        has_wb = 1; wb_val = r;
    } else if (op == 0x23) {
        uint32_t addr = (uint32_t)((int32_t)a + imm_s);
        uint32_t off = addr & 3;
        if (f3 == 0) mem_store(addr & ~3u, (b & 0xFF) << (8 * off), 1 << off);
        else if (f3 == 1) {
            uint32_t sh = (addr & 2) ? 2 : 0;
            mem_store(addr & ~3u, (b & 0xFFFF) << (8 * sh), 0x3 << sh);
        } else mem_store(addr & ~3u, b, 0xF);
    } else if (op == 0x63) {
        int take;
        switch (f3) {
            case 0: take = (a == b); break;
            case 1: take = (a != b); break;
            case 4: take = (sx(a, 32) < sx(b, 32)); break;
            case 5: take = (sx(a, 32) >= sx(b, 32)); break;
            case 6: take = (a < b); break;
            case 7: take = (a >= b); break;
            default: fprintf(stderr, "illegal branch funct3\n"); exit(1);
        }
        if (take) npc = (uint32_t)((int32_t)pc + imm_b);
    } else if (op == 0x37) {
        has_wb = 1; wb_val = imm_u;
    } else if (op == 0x17) {
        has_wb = 1; wb_val = pc + imm_u;
    } else if (op == 0x6F) {
        has_wb = 1; wb_val = npc;
        npc = (uint32_t)((int32_t)pc + imm_j);
    } else if (op == 0x67) {
        uint32_t t = (uint32_t)(((int32_t)a + imm_i) & ~1);
        has_wb = 1; wb_val = npc;
        npc = t;
    } else if (op == 0x73 || op == 0x0F) {
        /* ECALL/EBREAK/FENCE: no-op */
    } else {
        fprintf(stderr, "illegal instruction 0x%08x @0x%08x\n", inst, pc);
        exit(1);
    }

    if (has_wb && rd != 0) regs[rd] = wb_val;
    regs[0] = 0;
    if (trace && has_wb && rd != 0)
        printf("0x%08x: x%u <= 0x%08x\n", pc, rd, regs[rd]);
    return npc;
}

static void run(int maxcyc, int trace) {
    uint32_t pc = 0;
    int i;
    for (i = 0; i < maxcyc; i++) {
        pc = step(pc, trace);
        if (halted) break;
    }
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: iss prog.hex [--maxcyc N] [--dump regs.txt] [--trace]\n"); return 1; }
    const char *hexfile = argv[1];
    int maxcyc = 200000;
    const char *dumpfile = NULL;
    int trace = 0;
    int i;
    for (i = 2; i < argc; i++) {
        if (strcmp(argv[i], "--maxcyc") == 0 && i + 1 < argc) maxcyc = atoi(argv[++i]);
        else if (strcmp(argv[i], "--dump") == 0 && i + 1 < argc) dumpfile = argv[++i];
        else if (strcmp(argv[i], "--trace") == 0) trace = 1;
    }

    FILE *f = fopen(hexfile, "r");
    if (!f) { fprintf(stderr, "cannot open %s\n", hexfile); return 1; }
    char line[256];
    int n = 0;
    while (fgets(line, sizeof(line), f)) {
        char *end;
        unsigned long w = strtoul(line, &end, 16);
        if (end == line) continue;
        if (n >= MEM_WORDS) { fprintf(stderr, "hex file too large\n"); return 1; }
        mem[n++] = (uint32_t)w;
    }
    fclose(f);

    run(maxcyc, trace);

    printf("tohost = 0x%08x  ->  ", tohost_val);
    if (tohost_val == 1) printf("PASS\n");
    else printf("FAIL/test#%u\n", tohost_val >> 1);

    if (dumpfile) {
        FILE *df = fopen(dumpfile, "wb");
        if (!df) { fprintf(stderr, "cannot open %s\n", dumpfile); return 1; }
        for (i = 0; i < 32; i++) fprintf(df, "x%d %08x\n", i, regs[i]);
        fclose(df);
        fprintf(stderr, "wrote register dump to %s\n", dumpfile);
    }

    return tohost_val == 1 ? 0 : 1;
}
