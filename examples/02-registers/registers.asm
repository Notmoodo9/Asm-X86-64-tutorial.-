; =============================================================================
; Lesson 02 - registers, arithmetic and flags
;
; This program has no output. It is meant to be run inside WinDbg: every
; 'int3' is a checkpoint where the debugger stops so you can inspect registers.
; Type 'g' to continue to the next checkpoint.
;
; Running it OUTSIDE a debugger will crash at the first int3 - that's expected.
;
; Build:   fasm registers.asm
; Debug:   windbgx registers.exe      then 'g' repeatedly
; =============================================================================

format PE64 console
entry start

include 'win64a.inc'            ; only used here for the import macros at the end

section '.text' code readable executable

start:
        sub     rsp, 40

; --- Checkpoint 1: moving values around -------------------------------------
        mov     rax, 1122334455667788h  ; a full 64-bit immediate
        mov     rbx, rax                ; copy register to register
        mov     ecx, 0FFFFFFFFh         ; writing a 32-bit register...
        mov     rdx, -1                 ; rdx = FFFFFFFFFFFFFFFF
        mov     edx, 5                  ; ...ZEROES the upper 32 bits: rdx = 5
        mov     r8, -1
        mov     r8w, 5                  ; writing 16 bits keeps the upper bits
        mov     r9, -1
        mov     r9b, 5                  ; writing 8 bits keeps the upper bits too
        int3                            ; CHECKPOINT 1  -> r rax,rbx,rcx,rdx,r8,r9

; --- Checkpoint 2: add / sub / inc / dec / neg ------------------------------
        mov     eax, 100
        add     eax, 23                 ; 123
        sub     eax, 3                  ; 120
        inc     eax                     ; 121
        dec     eax                     ; 120
        mov     ebx, eax
        neg     ebx                     ; -120 (two's complement)
        int3                            ; CHECKPOINT 2  -> r eax, ebx ; ? ebx ; ? @ebx

; --- Checkpoint 3: multiplication and division ------------------------------
        mov     eax, 7
        imul    eax, eax, 6             ; three-operand form: eax = eax * 6 = 42
        mov     ecx, 12
        imul    ecx, eax                ; two-operand form: ecx = ecx * eax = 504

        mov     rax, 1000
        mov     rbx, 7
        xor     edx, edx                ; div divides RDX:RAX - so clear RDX first!
        div     rbx                     ; rax = 142 (quotient), rdx = 6 (remainder)
        int3                            ; CHECKPOINT 3  -> r rax, rdx, rcx

; --- Checkpoint 4: bitwise logic and shifts ---------------------------------
        mov     eax, 11110000b          ; binary literal (0F0h)
        and     eax, 00111100b          ; 00110000b = 30h
        or      eax, 1                  ; 31h
        xor     eax, 0FFh               ; flip low 8 bits -> 0CEh
        not     eax                     ; flip all 32 bits
        mov     ebx, 1
        shl     ebx, 10                 ; 1 << 10 = 1024
        mov     ecx, -64
        sar     ecx, 2                  ; arithmetic shift keeps the sign: -16
        mov     edx, -64
        shr     edx, 2                  ; logical shift fills with 0: big positive
        xor     r8d, r8d                ; the idiomatic way to zero a register
        int3                            ; CHECKPOINT 4

; --- Checkpoint 5..8: flags --------------------------------------------------
        mov     eax, 5
        sub     eax, 5                  ; result 0          -> ZF=1 (zr)
        int3                            ; CHECKPOINT 5  -> r efl ; r zf

        mov     eax, 3
        sub     eax, 5                  ; result negative   -> SF=1 (ng), CF=1 (cy)
        int3                            ; CHECKPOINT 6

        mov     al, 0FFh
        add     al, 1                   ; 8-bit wraparound  -> CF=1, ZF=1
        int3                            ; CHECKPOINT 7

        mov     al, 127
        add     al, 1                   ; signed overflow   -> OF=1 (ov), SF=1
        int3                            ; CHECKPOINT 8

; --- Checkpoint 9: exchange and sign/zero extension --------------------------
        mov     al, -2                  ; 0FEh
        movzx   ebx, al                 ; zero-extend: ebx = 000000FEh (254)
        movsx   ecx, al                 ; sign-extend: ecx = FFFFFFFEh (-2)
        movsxd  rdx, ecx                ; 32->64 sign-extend: rdx = -2
        mov     r8, 1
        mov     r9, 2
        xchg    r8, r9                  ; swap
        int3                            ; CHECKPOINT 9

; --- done: exit with the low byte of r9 (1) -----------------------------------
        mov     rcx, r9
        call    [ExitProcess]

section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL'        ; builds the descriptor table
        import  kernel32, ExitProcess, 'ExitProcess'   ; builds IAT + names
