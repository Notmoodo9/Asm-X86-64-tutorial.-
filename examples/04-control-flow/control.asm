; =============================================================================
; Lesson 04 - control flow and functions
;
; Computes a few things with hand-written functions, stores each result in
; memory, and exits with count_primes(100) = 25 as the exit code.
;
; The int3 checkpoints are behind a switch: set DEBUG = 1 to enable them
; (then run under WinDbg), DEBUG = 0 for a normal run.
;
; Build:   fasm control.asm
; Run:     control.exe  &  echo %ERRORLEVEL%     (prints 25)
; =============================================================================

format PE64 console
entry start

include 'win64a.inc'

DEBUG = 1

macro checkpoint {              ; a tiny macro: expands to int3 only if DEBUG
  if DEBUG
        int3
  end if
}

section '.text' code readable executable

; -----------------------------------------------------------------------------
; Program entry
; -----------------------------------------------------------------------------
start:
        sub     rsp, 40

        ; --- signed vs unsigned comparison --------------------------------
        mov     eax, -1
        cmp     eax, 1                  ; compute eax - 1, set flags, discard
        jl      .is_less_signed         ; signed:   -1 < 1         -> taken
        jmp     .after_signed
.is_less_signed:
        mov     [signed_result], 1
.after_signed:
        cmp     eax, 1
        jb      .is_below_unsigned      ; unsigned: 0FFFFFFFFh < 1 -> NOT taken
        jmp     .after_unsigned
.is_below_unsigned:
        mov     [unsigned_result], 1
.after_unsigned:
        checkpoint                      ; CP1: signed_result=1, unsigned_result=0

        ; --- calling our own functions -------------------------------------
        mov     rcx, -42
        call    abs_val
        mov     [r_abs], rax            ; 42

        mov     rcx, 3
        mov     rdx, 17
        mov     r8, 9
        call    max3
        mov     [r_max], rax            ; 17

        mov     rcx, 10
        call    factorial
        mov     [r_fact], rax           ; 3628800

        mov     rcx, 15
        call    fib
        mov     [r_fib], rax            ; 610

        mov     rcx, 2
        call    day_kind
        mov     [r_kind], rax           ; address of a string
        checkpoint                      ; CP2: inspect results

        mov     rcx, 100
        call    count_primes
        mov     [r_primes], rax         ; 25
        checkpoint                      ; CP3

        mov     rcx, rax                ; exit code = number of primes
        call    [ExitProcess]

; -----------------------------------------------------------------------------
; abs_val(rcx) -> rax = |rcx|            if/else with one branch
; -----------------------------------------------------------------------------
abs_val:
        mov     rax, rcx
        test    rax, rax                ; sets SF from rax (like cmp rax,0)
        jns     .done                   ; jump if not sign (>= 0)
        neg     rax
.done:
        ret

; -----------------------------------------------------------------------------
; max3(rcx, rdx, r8) -> rax = largest (signed)     uses cmov, no branches
; -----------------------------------------------------------------------------
max3:
        mov     rax, rcx
        cmp     rdx, rax
        cmovg   rax, rdx                ; if rdx > rax then rax = rdx
        cmp     r8, rax
        cmovg   rax, r8
        ret

; -----------------------------------------------------------------------------
; factorial(rcx) -> rax = rcx!           a counting loop
; -----------------------------------------------------------------------------
factorial:
        mov     eax, 1                  ; result
        cmp     rcx, 1
        jbe     .done                   ; 0! = 1! = 1
.loop:
        imul    rax, rcx                ; result *= n
        dec     rcx                     ; n-- (sets ZF when it reaches 0)
        cmp     rcx, 1
        ja      .loop                   ; while n > 1
.done:
        ret

; -----------------------------------------------------------------------------
; fib(rcx) -> rax                        recursion: fib(n) = fib(n-1)+fib(n-2)
;
; Calls itself, so it must save the registers it needs across the calls
; (rbx, rsi are "non-volatile": a function must preserve them) and keep the
; stack 16-byte aligned with 32 bytes of shadow space (lesson 05).
; -----------------------------------------------------------------------------
fib:
        cmp     rcx, 2
        jb      .base                   ; fib(0)=0, fib(1)=1
        push    rbx
        push    rsi
        sub     rsp, 40                 ; 8 (ret) + 16 (pushes) + 40 = 64: aligned
        mov     rbx, rcx                ; keep n in a preserved register
        lea     rcx, [rbx - 1]
        call    fib                     ; rax = fib(n-1)
        mov     rsi, rax
        lea     rcx, [rbx - 2]
        call    fib                     ; rax = fib(n-2)
        add     rax, rsi
        add     rsp, 40
        pop     rsi
        pop     rbx
        ret
.base:
        mov     rax, rcx
        ret

; -----------------------------------------------------------------------------
; day_kind(rcx = 0..6) -> rax = pointer to a string     a jump table (switch)
; -----------------------------------------------------------------------------
day_kind:
        cmp     rcx, 6
        ja      .invalid                ; unsigned compare also rejects negatives
        lea     rax, [.table]
        jmp     qword [rax + rcx*8]     ; jump to the address stored in the table
.weekend:
        lea     rax, [str_weekend]
        ret
.weekday:
        lea     rax, [str_weekday]
        ret
.invalid:
        lea     rax, [str_invalid]
        ret

        align 8
.table  dq .weekend, .weekday, .weekday, .weekday, .weekday, .weekday, .weekend

; -----------------------------------------------------------------------------
; is_prime(rcx) -> rax = 1 if prime, else 0        trial division
; -----------------------------------------------------------------------------
is_prime:
        cmp     rcx, 2
        jb      .no
        mov     r8, rcx                 ; n
        mov     r9, 2                   ; d
.loop:
        mov     rax, r9
        imul    rax, r9                 ; d*d
        cmp     rax, r8
        ja      .yes                    ; d*d > n -> no divisor found
        mov     rax, r8
        xor     edx, edx
        div     r9                      ; rdx = n mod d
        test    rdx, rdx
        jz      .no
        inc     r9
        jmp     .loop
.yes:
        mov     eax, 1
        ret
.no:
        xor     eax, eax
        ret

; -----------------------------------------------------------------------------
; count_primes(rcx) -> rax = number of primes below rcx
; -----------------------------------------------------------------------------
count_primes:
        push    rbx
        push    rsi
        push    rdi
        sub     rsp, 32                 ; 8 + 24 + 32 = 64: aligned
        mov     rbx, rcx                ; limit
        xor     esi, esi                ; count
        mov     edi, 2                  ; candidate
.next:
        cmp     rdi, rbx
        jae     .done
        mov     rcx, rdi
        call    is_prime
        add     rsi, rax                ; count += 0 or 1
        inc     rdi
        jmp     .next
.done:
        mov     rax, rsi
        add     rsp, 32
        pop     rdi
        pop     rsi
        pop     rbx
        ret

; -----------------------------------------------------------------------------
section '.data' data readable writeable

signed_result   dq 0
unsigned_result dq 0
r_abs           dq 0
r_max           dq 0
r_fact          dq 0
r_fib           dq 0
r_kind          dq 0
r_primes        dq 0

str_weekend     db 'weekend', 0
str_weekday     db 'weekday', 0
str_invalid     db 'invalid', 0

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL'
        import  kernel32, ExitProcess, 'ExitProcess'
