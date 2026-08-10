// reset entry: set sp, zero bss, call main
.section .text.init
.global _start
_start:
    la   sp, _stack_top # step stack pointer
    la   a0, _bss_start
    la   a1, _bss_end
1:  bge  a0, a1, 2f
    sw   zero, 0(a0) # zero BSS
    addi a0, a0, 4
    j    1b
2:  call main # hand off to C
3:  j    3b
