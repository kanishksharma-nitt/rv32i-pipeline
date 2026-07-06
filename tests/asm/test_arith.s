# test_arith.s - ALU register/immediate operations, self-checking.
        la    gp, tohost         # gp = tohost address (from linker)

        li    a3, 1
        addi  t0, x0, 100
        addi  t1, x0, -40
        add   t2, t0, t1         # 60
        li    s0, 60
        bne   t2, s0, fail

        li    a3, 2
        sub   t2, t0, t1         # 140
        li    s0, 140
        bne   t2, s0, fail

        li    a3, 3
        li    t0, 0xF0F0F0F0
        li    t1, 0x0FF00FF0
        and   t2, t0, t1         # 0x00F000F0
        li    s0, 0x00F000F0
        bne   t2, s0, fail
        or    t2, t0, t1         # 0xFFF0FFF0
        li    a3, 4
        li    s0, 0xFFF0FFF0
        bne   t2, s0, fail
        xor   t2, t0, t1         # 0xFF00FF00
        li    a3, 5
        li    s0, 0xFF00FF00
        bne   t2, s0, fail

        li    a3, 6
        li    t0, 1
        slli  t2, t0, 31         # 0x80000000
        li    s0, 0x80000000
        bne   t2, s0, fail
        srai  t2, t2, 31         # 0xFFFFFFFF (arithmetic)
        li    a3, 7
        li    s0, -1
        bne   t2, s0, fail
        li    t0, 0x80000000
        srli  t2, t0, 28         # 0x00000008
        li    a3, 8
        li    s0, 8
        bne   t2, s0, fail

        li    a3, 9
        li    t0, -5
        li    t1, 3
        slt   t2, t0, t1         # signed: -5<3 => 1
        li    s0, 1
        bne   t2, s0, fail
        sltu  t2, t0, t1         # unsigned: huge<3 => 0
        li    a3, 10
        bne   t2, x0, fail

        li    a3, 11
        slti  t2, t1, 5          # 3<5 => 1
        li    s0, 1
        bne   t2, s0, fail

pass:   li    t0, 1
        sw    t0, 0(gp)
        j     pass
fail:   slli  a3, a3, 1
        ori   a3, a3, 1
        sw    a3, 0(gp)
        j     fail
