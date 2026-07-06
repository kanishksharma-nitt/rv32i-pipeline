#!/usr/bin/env python3
"""Rebuild the register file from a Spike commit log and diff it against the
RTL's register dump.

    compare_regs.py --spike-log spike.log --rtl test.rtl.dump   # compare
    compare_regs.py --spike-log spike.log --emit test.dump       # emit golden
"""
import argparse
import re
import sys

# Commit line: "core 0: 3 0x80000008 (0x006283b3) x7 0x00000032".
COMMIT_RE = re.compile(r"^core\s+\d+:\s+\d+\s+(0x[0-9a-fA-F]+)\s")
# Register write; the leading boundary avoids the "x" inside a "0x..." address.
REG_RE = re.compile(r"(?:^|\s)x(\d{1,2})\s+(0x[0-9a-fA-F]+)")


def regs_from_spike(path, pc_min):
    regs = [0] * 32
    with open(path) as f:
        for line in f:
            m = COMMIT_RE.match(line)
            if not m:
                continue
            pc = int(m.group(1), 16)
            if pc < pc_min:
                continue  # skip Spike's reset ROM
            rm = REG_RE.search(line[m.end():])
            if rm:
                idx = int(rm.group(1))
                if 0 <= idx < 32:
                    regs[idx] = int(rm.group(2), 16) & 0xFFFFFFFF
    regs[0] = 0
    return regs


def regs_from_dump(path):
    regs = [0] * 32
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            name, val = line.split()
            regs[int(name[1:])] = int(val, 16) & 0xFFFFFFFF
    return regs


def fmt(regs):
    return "".join(f"x{i} {regs[i]:08x}\n" for i in range(32))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spike-log", required=True)
    ap.add_argument("--rtl", help="RTL register dump to compare against")
    ap.add_argument("--emit", help="write the Spike-derived dump to this file")
    ap.add_argument("--pc-min", default="0x80000000",
                    help="ignore register writes below this PC (reset ROM)")
    args = ap.parse_args()

    spike = regs_from_spike(args.spike_log, int(args.pc_min, 0))

    if args.emit:
        with open(args.emit, "w") as f:
            f.write(fmt(spike))
        return 0

    if not args.rtl:
        ap.error("either --rtl or --emit is required")

    rtl = regs_from_dump(args.rtl)
    diffs = [(i, rtl[i], spike[i]) for i in range(32) if rtl[i] != spike[i]]
    if diffs:
        print("MISMATCH (rtl vs spike):")
        for i, r, s in diffs:
            print(f"  x{i}: rtl={r:08x} spike={s:08x}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
