# test_branch.s - branches, JAL/JALR, forwarding around control flow.
        la    gp, tohost

        # count a loop 0..9, sum = 45
        li    a3, 1
        li    t0, 0              # i
        li    t1, 0              # sum
loop:   add   t1, t1, t0
        addi  t0, t0, 1
        li    s1, 10
        blt   t0, s1, loop
        li    s0, 45
        bne   t1, s0, fail

        # function call via jal/ret: add5(x) = x+5
        li    a3, 2
        li    a0, 20
        jal   ra, add5
        li    s0, 25
        bne   a0, s0, fail

        # forward taken/branch-not-taken corners
        li    a3, 3
        li    t0, 7
        beq   t0, t0, l1
        j     fail               # must be skipped
l1:     bne   t0, t0, fail       # not taken
        bgeu  t0, x0, l2
        j     fail
l2:     nop

pass:   li    t0, 1
        sw    t0, 0(gp)
        j     pass
add5:   addi  a0, a0, 5
        ret
fail:   slli  a3, a3, 1
        ori   a3, a3, 1
        sw    a3, 0(gp)
        j     fail
