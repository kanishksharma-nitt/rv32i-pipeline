/* Two-pass RV32I assembler -> $readmemh hex.  assembler prog.s -o prog.hex */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <stdint.h>
#include <stdarg.h>

static const char *g_outfile = NULL;

#define MAX_LABELS 1024
#define MAX_INSTR  4096
#define MAX_OPS    32
#define MAX_WORDS  65536
#define LINE_LEN   1024
#define TOK_LEN    96

typedef struct { char name[64]; long long value; } Label;
static Label labels[MAX_LABELS];
static int nlabels = 0;

typedef struct {
    long long pc;
    char mnem[16];
    char ops[MAX_OPS][TOK_LEN];
    int nops;
} Instr;
static Instr prog[MAX_INSTR];
static int nprog = 0;

static uint32_t words[MAX_WORDS];

typedef struct { const char *m; int op, f3, f7; } OpEntry;

static const OpEntry RTAB[] = {
    {"add", 0x33, 0x0, 0x00}, {"sub", 0x33, 0x0, 0x20},
    {"sll", 0x33, 0x1, 0x00}, {"slt", 0x33, 0x2, 0x00},
    {"sltu", 0x33, 0x3, 0x00}, {"xor", 0x33, 0x4, 0x00},
    {"srl", 0x33, 0x5, 0x00}, {"sra", 0x33, 0x5, 0x20},
    {"or", 0x33, 0x6, 0x00}, {"and", 0x33, 0x7, 0x00},
};
static const OpEntry ITAB[] = {
    {"addi", 0x13, 0x0, 0}, {"slti", 0x13, 0x2, 0}, {"sltiu", 0x13, 0x3, 0},
    {"xori", 0x13, 0x4, 0}, {"ori", 0x13, 0x6, 0}, {"andi", 0x13, 0x7, 0},
};
static const OpEntry ISHTAB[] = {
    {"slli", 0x13, 0x1, 0x00}, {"srli", 0x13, 0x5, 0x00}, {"srai", 0x13, 0x5, 0x20},
};
static const OpEntry LDTAB[] = {
    {"lb", 0x03, 0x0, 0}, {"lh", 0x03, 0x1, 0}, {"lw", 0x03, 0x2, 0},
    {"lbu", 0x03, 0x4, 0}, {"lhu", 0x03, 0x5, 0},
};
static const OpEntry STAB[] = {
    {"sb", 0x23, 0x0, 0}, {"sh", 0x23, 0x1, 0}, {"sw", 0x23, 0x2, 0},
};
static const OpEntry BTAB[] = {
    {"beq", 0x63, 0x0, 0}, {"bne", 0x63, 0x1, 0}, {"blt", 0x63, 0x4, 0},
    {"bge", 0x63, 0x5, 0}, {"bltu", 0x63, 0x6, 0}, {"bgeu", 0x63, 0x7, 0},
};

static void die(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

static char *trim(char *s) {
    while (isspace((unsigned char)*s)) s++;
    if (*s == 0) return s;
    char *e = s + strlen(s) - 1;
    while (e > s && isspace((unsigned char)*e)) *e-- = 0;
    return s;
}

static void tolower_str(char *s) { for (; *s; s++) *s = (char)tolower((unsigned char)*s); }
static int streq(const char *a, const char *b) { return strcmp(a, b) == 0; }

static const OpEntry *find_op(const OpEntry *tab, int n, const char *m) {
    int i;
    for (i = 0; i < n; i++) if (streq(tab[i].m, m)) return &tab[i];
    return NULL;
}

static int find_label(const char *name) {
    int i;
    for (i = 0; i < nlabels; i++) if (streq(labels[i].name, name)) return i;
    return -1;
}

static void add_label(const char *name, long long value) {
    if (nlabels >= MAX_LABELS) die("too many labels");
    size_t len = strlen(name);
    if (len >= sizeof(labels[nlabels].name)) len = sizeof(labels[nlabels].name) - 1;
    memcpy(labels[nlabels].name, name, len);
    labels[nlabels].name[len] = 0;
    labels[nlabels].value = value;
    nlabels++;
}

static int reg(const char *tok0) {
    char tok[64];
    strncpy(tok, tok0, sizeof(tok) - 1);
    tok[sizeof(tok) - 1] = 0;
    tolower_str(trim(tok));
    static const char *names[] = {
        "zero", "ra", "sp", "gp", "tp", "t0", "t1", "t2", "s0", "fp", "s1",
        "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "s2", "s3", "s4",
        "s5", "s6", "s7", "s8", "s9", "s10", "s11", "t3", "t4", "t5", "t6"
    };
    static const int idx[] = {
        0, 1, 2, 3, 4, 5, 6, 7, 8, 8, 9,
        10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20,
        21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31
    };
    size_t i;
    for (i = 0; i < sizeof(names) / sizeof(names[0]); i++)
        if (streq(tok, names[i])) return idx[i];
    if (tok[0] == 'x' && isdigit((unsigned char)tok[1])) {
        int n = atoi(tok + 1);
        if (n >= 0 && n < 32) return n;
    }
    die("bad register: %s", tok0);
    return 0;
}

/* Mirrors Python's imm(): checks the label table first (when use_labels),
 * falls back to a numeric literal. rel subtracts pc for pc-relative fields. */
static long long resolve_imm(const char *tok0, long long pc, int rel, int use_labels) {
    char tok[TOK_LEN];
    strncpy(tok, tok0, sizeof(tok) - 1);
    tok[sizeof(tok) - 1] = 0;
    char *t = trim(tok);
    if (use_labels) {
        int li = find_label(t);
        if (li >= 0) return rel ? labels[li].value - pc : labels[li].value;
    }
    char *end;
    long long v = strtoll(t, &end, 0);
    if (end == t) die("bad immediate/label: %s", tok0);
    return v;
}

static long long label_value_or_die(const char *name) {
    int li = find_label(name);
    if (li < 0) die("undefined label: %s", name);
    return labels[li].value;
}

/* offset(reg) memory operand, e.g. "-16(sp)". Returns 1 on match. */
static int parse_mem(const char *tok, char *off, char *regname) {
    const char *p = strchr(tok, '(');
    if (!p) return 0;
    const char *q = strchr(p, ')');
    if (!q) return 0;
    size_t olen = (size_t)(p - tok);
    if (olen >= TOK_LEN) olen = TOK_LEN - 1;
    memcpy(off, tok, olen); off[olen] = 0; strcpy(off, trim(off));
    size_t rlen = (size_t)(q - (p + 1));
    if (rlen >= TOK_LEN) rlen = TOK_LEN - 1;
    memcpy(regname, p + 1, rlen); regname[rlen] = 0; strcpy(regname, trim(regname));
    return 1;
}

static uint32_t u32(long long x) { return (uint32_t)(x & 0xFFFFFFFFLL); }

static uint32_t enc_r(int op, int f3, int f7, int rd, int rs1, int rs2) {
    return u32(((long long)f7 << 25) | ((long long)rs2 << 20) | ((long long)rs1 << 15) |
               ((long long)f3 << 12) | ((long long)rd << 7) | op);
}
static uint32_t enc_i(int op, int f3, int rd, int rs1, long long im) {
    return u32(((im & 0xFFF) << 20) | ((long long)rs1 << 15) | ((long long)f3 << 12) |
               ((long long)rd << 7) | op);
}
static uint32_t enc_ish(int op, int f3, int f7, int rd, int rs1, long long sh) {
    return u32(((long long)f7 << 25) | ((sh & 0x1F) << 20) | ((long long)rs1 << 15) |
               ((long long)f3 << 12) | ((long long)rd << 7) | op);
}
static uint32_t enc_s(int op, int f3, int rs1, int rs2, long long im) {
    im &= 0xFFF;
    return u32(((im >> 5) << 25) | ((long long)rs2 << 20) | ((long long)rs1 << 15) |
               ((long long)f3 << 12) | ((im & 0x1F) << 7) | op);
}
static uint32_t enc_b(int op, int f3, int rs1, int rs2, long long im) {
    im &= 0x1FFF;
    long long b12 = (im >> 12) & 1, b11 = (im >> 11) & 1, b10_5 = (im >> 5) & 0x3F, b4_1 = (im >> 1) & 0xF;
    return u32((b12 << 31) | (b10_5 << 25) | ((long long)rs2 << 20) | ((long long)rs1 << 15) |
               ((long long)f3 << 12) | (b4_1 << 8) | (b11 << 7) | op);
}
static uint32_t enc_u(int op, int rd, long long im) {
    return u32((u32(im) & 0xFFFFF000u) | ((long long)rd << 7) | op);
}
static uint32_t enc_j(int op, int rd, long long im) {
    im &= 0x1FFFFF;
    long long b20 = (im >> 20) & 1, b10_1 = (im >> 1) & 0x3FF, b11 = (im >> 11) & 1, b19_12 = (im >> 12) & 0xFF;
    return u32((b20 << 31) | (b10_1 << 21) | (b11 << 20) | (b19_12 << 12) | ((long long)rd << 7) | op);
}

static int li_size(long long value) {
    uint32_t v = u32(value);
    int32_t sval = (int32_t)v;
    return (sval >= -2048 && sval < 2048) ? 1 : 2;
}

static int instr_size(const char *mnem, char ops[][TOK_LEN], int nops) {
    (void)nops;
    if (streq(mnem, "li")) {
        char *end;
        long long v = strtoll(ops[1], &end, 0);
        return li_size(v);
    }
    if (streq(mnem, "la")) return 2;
    return 1;
}

static void split_ops(char *rest, char ops[][TOK_LEN], int *nops) {
    *nops = 0;
    char *tok = strtok(rest, ",");
    while (tok) {
        char *t = trim(tok);
        strncpy(ops[*nops], t, TOK_LEN - 1);
        ops[*nops][TOK_LEN - 1] = 0;
        (*nops)++;
        tok = strtok(NULL, ",");
    }
}

static void first_pass(FILE *f) {
    char raw[LINE_LEN];
    long long pc = 0;
    while (fgets(raw, sizeof(raw), f)) {
        char *hc = strstr(raw, "#");
        char *sc = strstr(raw, "//");
        if (hc && (!sc || hc < sc)) *hc = 0;
        else if (sc) *sc = 0;
        char *line = trim(raw);
        if (*line == 0) continue;

        for (;;) {
            char *p = line;
            while (isalnum((unsigned char)*p) || *p == '_') p++;
            if (p == line || *p != ':') break;
            char name[64];
            size_t len = (size_t)(p - line);
            if (len >= sizeof(name)) len = sizeof(name) - 1;
            memcpy(name, line, len); name[len] = 0;
            add_label(name, pc);
            line = trim(p + 1);
        }
        if (*line == 0) continue;

        char *sp = line;
        while (*sp && !isspace((unsigned char)*sp)) sp++;
        char mnem[16];
        size_t mlen = (size_t)(sp - line);
        if (mlen >= sizeof(mnem)) mlen = sizeof(mnem) - 1;
        memcpy(mnem, line, mlen); mnem[mlen] = 0;
        tolower_str(mnem);
        char *rest = trim(sp);

        char ops[MAX_OPS][TOK_LEN];
        int nops;
        split_ops(rest, ops, &nops);

        if (streq(mnem, ".word")) {
            if (nprog >= MAX_INSTR) die("too many instructions");
            prog[nprog].pc = pc;
            strcpy(prog[nprog].mnem, mnem);
            memcpy(prog[nprog].ops, ops, sizeof(ops));
            prog[nprog].nops = nops;
            nprog++;
            pc += 4 * nops;
        } else if (streq(mnem, ".align")) {
            long long a = 1LL << strtoll(ops[0], NULL, 0);
            while (pc % a) pc += 4;
        } else {
            if (nprog >= MAX_INSTR) die("too many instructions");
            prog[nprog].pc = pc;
            strcpy(prog[nprog].mnem, mnem);
            memcpy(prog[nprog].ops, ops, sizeof(ops));
            prog[nprog].nops = nops;
            nprog++;
            pc += 4 * instr_size(mnem, ops, nops);
        }
    }
    prog[nprog].pc = pc; /* sentinel: final size */
}

static void assemble(const char *path) {
    FILE *f = fopen(path, "r");
    if (!f) die("cannot open %s", path);
    first_pass(f);
    fclose(f);

    long long size = prog[nprog].pc;
    int i;
    for (i = 0; i < nprog; i++) {
        long long pc = prog[i].pc;
        char (*ops)[TOK_LEN] = prog[i].ops;
        int nops = prog[i].nops;
        const char *mnem = prog[i].mnem;
        const OpEntry *e;

        if (streq(mnem, ".word")) {
            int k;
            for (k = 0; k < nops; k++)
                words[(pc + 4 * k) / 4] = u32(resolve_imm(ops[k], pc, 0, 1));
        } else if ((e = find_op(RTAB, sizeof(RTAB) / sizeof(RTAB[0]), mnem))) {
            words[pc / 4] = enc_r(e->op, e->f3, e->f7, reg(ops[0]), reg(ops[1]), reg(ops[2]));
        } else if ((e = find_op(ITAB, sizeof(ITAB) / sizeof(ITAB[0]), mnem))) {
            words[pc / 4] = enc_i(e->op, e->f3, reg(ops[0]), reg(ops[1]), resolve_imm(ops[2], pc, 0, 1));
        } else if ((e = find_op(ISHTAB, sizeof(ISHTAB) / sizeof(ISHTAB[0]), mnem))) {
            words[pc / 4] = enc_ish(e->op, e->f3, e->f7, reg(ops[0]), reg(ops[1]), resolve_imm(ops[2], pc, 0, 0));
        } else if ((e = find_op(LDTAB, sizeof(LDTAB) / sizeof(LDTAB[0]), mnem))) {
            char off[TOK_LEN], rn[TOK_LEN];
            if (!parse_mem(ops[1], off, rn)) die("bad memory operand: %s", ops[1]);
            words[pc / 4] = enc_i(e->op, e->f3, reg(ops[0]), reg(rn), resolve_imm(off, pc, 0, 1));
        } else if ((e = find_op(STAB, sizeof(STAB) / sizeof(STAB[0]), mnem))) {
            char off[TOK_LEN], rn[TOK_LEN];
            if (!parse_mem(ops[1], off, rn)) die("bad memory operand: %s", ops[1]);
            words[pc / 4] = enc_s(e->op, e->f3, reg(rn), reg(ops[0]), resolve_imm(off, pc, 0, 1));
        } else if ((e = find_op(BTAB, sizeof(BTAB) / sizeof(BTAB[0]), mnem))) {
            words[pc / 4] = enc_b(e->op, e->f3, reg(ops[0]), reg(ops[1]), resolve_imm(ops[2], pc, 1, 1));
        } else if (streq(mnem, "lui")) {
            words[pc / 4] = enc_u(0x37, reg(ops[0]), resolve_imm(ops[1], pc, 0, 0) << 12);
        } else if (streq(mnem, "auipc")) {
            words[pc / 4] = enc_u(0x17, reg(ops[0]), resolve_imm(ops[1], pc, 0, 0) << 12);
        } else if (streq(mnem, "jal")) {
            int rd; const char *tgt;
            if (nops == 1) { rd = 1; tgt = ops[0]; } else { rd = reg(ops[0]); tgt = ops[1]; }
            words[pc / 4] = enc_j(0x6F, rd, resolve_imm(tgt, pc, 1, 1));
        } else if (streq(mnem, "jalr")) {
            if (nops == 1) {
                words[pc / 4] = enc_i(0x67, 0, 1, reg(ops[0]), 0);
            } else {
                char off[TOK_LEN], rn[TOK_LEN];
                if (parse_mem(ops[1], off, rn)) {
                    words[pc / 4] = enc_i(0x67, 0, reg(ops[0]), reg(rn), resolve_imm(off, pc, 0, 0));
                } else {
                    long long im = nops > 2 ? resolve_imm(ops[2], pc, 0, 0) : 0;
                    words[pc / 4] = enc_i(0x67, 0, reg(ops[0]), reg(ops[1]), im);
                }
            }
        } else if (streq(mnem, "nop")) {
            words[pc / 4] = enc_i(0x13, 0, 0, 0, 0);
        } else if (streq(mnem, "li")) {
            long long v = resolve_imm(ops[1], pc, 0, 0);
            int rd = reg(ops[0]);
            if (li_size(v) == 1) {
                words[pc / 4] = enc_i(0x13, 0, rd, 0, v & 0xFFF);
            } else {
                long long lo = v & 0xFFF;
                long long hi = (v - (lo & 0x800 ? lo - 4096 : lo)) >> 12;
                words[pc / 4] = enc_u(0x37, rd, (hi & 0xFFFFF) << 12);
                words[pc / 4 + 1] = enc_i(0x13, 0, rd, rd, lo);
            }
        } else if (streq(mnem, "la")) {
            int rd = reg(ops[0]);
            long long tgt = label_value_or_die(ops[1]);
            long long off = tgt - pc;
            long long hi = (off + 0x800) >> 12;
            long long lo = off - (hi << 12);
            words[pc / 4] = enc_u(0x17, rd, (hi & 0xFFFFF) << 12);
            words[pc / 4 + 1] = enc_i(0x13, 0, rd, rd, lo & 0xFFF);
        } else if (streq(mnem, "mv")) {
            words[pc / 4] = enc_i(0x13, 0, reg(ops[0]), reg(ops[1]), 0);
        } else if (streq(mnem, "not")) {
            words[pc / 4] = enc_i(0x13, 0x4, reg(ops[0]), reg(ops[1]), -1);
        } else if (streq(mnem, "neg")) {
            words[pc / 4] = enc_r(0x33, 0x0, 0x20, reg(ops[0]), 0, reg(ops[1]));
        } else if (streq(mnem, "seqz")) {
            words[pc / 4] = enc_i(0x13, 0x3, reg(ops[0]), reg(ops[1]), 1);
        } else if (streq(mnem, "snez")) {
            words[pc / 4] = enc_r(0x33, 0x3, 0x00, reg(ops[0]), 0, reg(ops[1]));
        } else if (streq(mnem, "j")) {
            words[pc / 4] = enc_j(0x6F, 0, resolve_imm(ops[0], pc, 1, 1));
        } else if (streq(mnem, "jr")) {
            words[pc / 4] = enc_i(0x67, 0, 0, reg(ops[0]), 0);
        } else if (streq(mnem, "ret")) {
            words[pc / 4] = enc_i(0x67, 0, 0, 1, 0);
        } else if (streq(mnem, "beqz") || streq(mnem, "bnez")) {
            int f3 = streq(mnem, "beqz") ? 0x0 : 0x1;
            words[pc / 4] = enc_b(0x63, f3, reg(ops[0]), 0, resolve_imm(ops[1], pc, 1, 1));
        } else if (streq(mnem, "blez") || streq(mnem, "bgez") || streq(mnem, "bltz") || streq(mnem, "bgtz")) {
            long long tgt = resolve_imm(ops[1], pc, 1, 1);
            if (streq(mnem, "blez")) words[pc / 4] = enc_b(0x63, 0x5, 0, reg(ops[0]), tgt);
            else if (streq(mnem, "bgez")) words[pc / 4] = enc_b(0x63, 0x5, reg(ops[0]), 0, tgt);
            else if (streq(mnem, "bltz")) words[pc / 4] = enc_b(0x63, 0x4, reg(ops[0]), 0, tgt);
            else words[pc / 4] = enc_b(0x63, 0x4, 0, reg(ops[0]), tgt);
        } else if (streq(mnem, "ecall")) {
            words[pc / 4] = enc_i(0x73, 0, 0, 0, 0);
        } else {
            die("unsupported mnemonic @0x%llx: %s", pc, mnem);
        }
    }

    long long nwords = (size + 3) / 4;
    if (nwords > MAX_WORDS) die("program too large");

    const char *out = g_outfile;
    FILE *of = out ? fopen(out, "wb") : stdout;
    if (!of) die("cannot open output %s", out);
    for (i = 0; i < nwords; i++) fprintf(of, "%08x\n", words[i]);
    if (out) {
        fclose(of);
        fprintf(stderr, "wrote %s: %lld words\n", out, nwords);
    }
}

int main(int argc, char **argv) {
    if (argc < 2) { fprintf(stderr, "usage: assembler prog.s [-o out.hex]\n"); return 1; }
    const char *src = argv[1];
    int i;
    for (i = 2; i < argc; i++) {
        if (streq(argv[i], "-o") && i + 1 < argc) g_outfile = argv[++i];
    }
    assemble(src);
    return 0;
}
