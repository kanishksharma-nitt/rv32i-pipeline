# test_fib.s - iterative + recursive Fibonacci, self-checking.
        la    gp, tohost

        # iterative fib(10) = 55
        li    a3, 1
        li    a0, 10
        jal   ra, fib_iter
        li    s0, 55
        bne   a0, s0, fail

        # recursive fib(12) = 144 (exercises stack, calls, load-use on stack)
        li    a3, 2
        li    sp, 0x80007000     # stack top in DRAM, clear of code/data/tohost
        li    a0, 12
        jal   ra, fib_rec
        li    s0, 144
        bne   a0, s0, fail

pass:   li    t0, 1
        sw    t0, 0(gp)
        j     pass

# a0 = n ; returns fib(n) iteratively
fib_iter:
        li    t0, 0              # a
        li    t1, 1              # b
        mv    t2, a0
fi_loop:
        beq   t2, x0, fi_done
        add   t3, t0, t1
        mv    t0, t1
        mv    t1, t3
        addi  t2, t2, -1
        j     fi_loop
fi_done:
        mv    a0, t0
        ret

# a0 = n ; returns fib(n) recursively
fib_rec:
        addi  sp, sp, -16
        sw    ra, 12(sp)
        sw    s0, 8(sp)
        li    t0, 2
        blt   a0, t0, fr_base    # n < 2 -> return n
        mv    s0, a0
        addi  a0, s0, -1
        jal   ra, fib_rec        # fib(n-1)
        sw    a0, 4(sp)          # save
        addi  a0, s0, -2
        jal   ra, fib_rec        # fib(n-2)
        lw    t1, 4(sp)
        add   a0, a0, t1
        j     fr_ret
fr_base:
        # a0 already = n
        nop
fr_ret:
        lw    ra, 12(sp)
        lw    s0, 8(sp)
        addi  sp, sp, 16
        ret

fail:   slli  a3, a3, 1
        ori   a3, a3, 1
        sw    a3, 0(gp)
        j     fail
