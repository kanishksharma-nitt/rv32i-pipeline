# test_hazard.s - forwarding and load-use stall stress.
        la    gp, tohost
        la    s2, scratch

        # back-to-back dependent ALU ops (EX/MEM and MEM/WB forwarding)
        li    a3, 1
        li    t0, 1
        addi  t0, t0, 1          # 2  (forward EX/MEM)
        addi  t0, t0, 1          # 3
        addi  t0, t0, 1          # 4
        addi  t0, t0, 1          # 5
        li    s0, 5
        bne   t0, s0, fail

        # load-use hazard: result used immediately (needs 1 stall + fwd)
        li    a3, 2
        li    t1, 0xCAFEBABE
        sw    t1, 0(s2)
        lw    t2, 0(s2)
        addi  t3, t2, 0          # depends on load -> load-use
        bne   t3, t1, fail

        # load then use as branch operand
        li    a3, 3
        lw    t2, 0(s2)
        bne   t2, t1, fail

        # store data forwarded from immediately-preceding ALU op
        li    a3, 4
        li    t0, 0x55667788
        sw    t0, 4(s2)
        lw    t1, 4(s2)
        bne   t1, t0, fail

        # chain through a function return value (forward JALR link path)
        li    a3, 5
        li    a0, 0
        jal   ra, inc
        jal   ra, inc
        jal   ra, inc
        li    s0, 3
        bne   a0, s0, fail

pass:   li    t0, 1
        sw    t0, 0(gp)
        j     pass
inc:    addi  a0, a0, 1
        ret
fail:   slli  a3, a3, 1
        ori   a3, a3, 1
        sw    a3, 0(gp)
        j     fail

        .align 4
scratch: .word 0, 0, 0, 0
