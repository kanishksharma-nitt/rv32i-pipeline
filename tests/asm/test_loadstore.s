# test_loadstore.s - byte/half/word load-store with sign/zero extension.
        la    gp, tohost
        la    s2, data           # base pointer to data region

        # store a word, read it back
        li    a3, 1
        li    t0, 0x12345678
        sw    t0, 0(s2)
        lw    t1, 0(s2)
        bne   t1, t0, fail

        # byte lanes via LBU
        li    a3, 2
        lbu   t1, 0(s2)          # 0x78
        li    s0, 0x78
        bne   t1, s0, fail
        lbu   t1, 1(s2)          # 0x56
        li    a3, 3
        li    s0, 0x56
        bne   t1, s0, fail
        lbu   t1, 3(s2)          # 0x12
        li    a3, 4
        li    s0, 0x12
        bne   t1, s0, fail

        # signed byte: store 0x80 -> LB sign-extends
        li    a3, 5
        li    t0, 0x80
        sb    t0, 4(s2)
        lb    t1, 4(s2)
        li    s0, -128
        bne   t1, s0, fail
        lbu   t1, 4(s2)          # zero-extended 0x80
        li    a3, 6
        li    s0, 0x80
        bne   t1, s0, fail

        # halfword store/load + sign extension
        li    a3, 7
        li    t0, 0xFFFF8001
        sh    t0, 8(s2)
        lh    t1, 8(s2)          # 0x8001 -> sign-extend
        li    s0, 0xFFFF8001
        bne   t1, s0, fail
        lhu   t1, 8(s2)          # 0x00008001
        li    a3, 8
        li    s0, 0x8001
        bne   t1, s0, fail

        # store byte must not clobber neighbours
        li    a3, 9
        li    t0, 0x0
        sw    t0, 12(s2)
        li    t0, 0xAA
        sb    t0, 13(s2)         # only byte1
        lw    t1, 12(s2)
        li    s0, 0x0000AA00
        bne   t1, s0, fail

pass:   li    t0, 1
        sw    t0, 0(gp)
        j     pass
fail:   slli  a3, a3, 1
        ori   a3, a3, 1
        sw    a3, 0(gp)
        j     fail

        .align 4
data:   .word 0, 0, 0, 0, 0, 0, 0, 0
