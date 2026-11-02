; =============================================================================
; Lesson 07 - an interactive console calculator
;
; Reads lines like   12 * 34   or   -100 / 7   and prints the result.
; An empty line quits.
;
; Build:   fasm calc.asm
; Run:     calc.exe
; =============================================================================

format PE64 console
entry start

include 'win64a.inc'

LINE_MAX = 255

section '.text' code readable executable

start:
        sub     rsp, 8

        fastcall print_z, banner

.prompt:
        fastcall print_z, prompt_str
        fastcall read_line, line, LINE_MAX
        test    rax, rax
        jz      .quit                   ; empty line -> quit

        ; --- parse:  <number> <op> <number> --------------------------------
        fastcall skip_spaces, line
        fastcall parse_i64, rax         ; rax = value, rdx = rest of line
        mov     [num_a], rax
        fastcall skip_spaces, rdx
        movzx   ebx, byte [rax]         ; ebx = operator character
        inc     rax
        fastcall skip_spaces, rax
        fastcall parse_i64, rax
        mov     [num_b], rax

        ; --- dispatch on the operator ---------------------------------------
        mov     rax, [num_a]
        mov     rcx, [num_b]
        cmp     bl, '+'
        je      .add
        cmp     bl, '-'
        je      .sub
        cmp     bl, '*'
        je      .mul
        cmp     bl, '/'
        je      .div
        cmp     bl, '%'
        je      .mod
        fastcall print_z, err_op
        jmp     .prompt

.add:   add     rax, rcx
        jmp     .show
.sub:   sub     rax, rcx
        jmp     .show
.mul:   imul    rax, rcx
        jmp     .show
.div:   test    rcx, rcx
        jz      .divzero
        cqo                             ; sign-extend rax into rdx:rax
        idiv    rcx                     ; rax = quotient
        jmp     .show
.mod:   test    rcx, rcx
        jz      .divzero
        cqo
        idiv    rcx
        mov     rax, rdx                ; remainder
        jmp     .show

.divzero:
        fastcall print_z, err_div
        jmp     .prompt

.show:
        mov     [result], rax
        fastcall print_z, equals_str
        fastcall print_i64, [result]
        fastcall print_z, hex_str
        fastcall print_hex, [result]
        fastcall print_nl
        jmp     .prompt

.quit:
        invoke  ExitProcess, 0

        include '..\common\console.inc'

; -----------------------------------------------------------------------------
section '.data' data readable writeable

banner          db 'asm calc - enter e.g.  12 * 34   (empty line quits)', 13, 10, 0
prompt_str      db '> ', 0
equals_str      db '= ', 0
hex_str         db '   hex ', 0
err_op          db 'unknown operator (use + - * / %)', 13, 10, 0
err_div         db 'division by zero', 13, 10, 0

num_a           dq ?
num_b           dq ?
result          dq ?
line            rb LINE_MAX + 1

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL'
        include 'api\kernel32.inc'
