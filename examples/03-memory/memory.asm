; =============================================================================
; Lesson 03 - memory, addressing modes and the stack
;
; Run inside WinDbg; each int3 is a checkpoint ('g' to continue).
;
; Build:   fasm memory.asm
; Debug:   windbgx memory.exe
; =============================================================================

format PE64 console
entry start

include 'win64a.inc'

section '.text' code readable executable

start:
        sub     rsp, 40

; --- Checkpoint 1: little-endian -------------------------------------------
        ; 'magic' is a qword. To read part of it we must say which size we want.
        mov     al, byte [magic]        ; lowest-addressed byte = 88h
        mov     bx, word [magic]        ; 7788h
        mov     ecx, dword [magic]      ; 55667788h
        mov     rdx, [magic]            ; size known from the label: qword
        int3                            ; CHECKPOINT 1  -> db magic? (see lesson)

; --- Checkpoint 2: sum an array with base + index*scale ----------------------
        lea     rsi, [numbers]          ; rsi = ADDRESS of numbers (no memory read)
        xor     eax, eax                ; sum = 0
        xor     ecx, ecx                ; i = 0
.sum:
        add     eax, [rsi + rcx*4]      ; sum += numbers[i]   (dword elements)
        inc     ecx
        cmp     ecx, NUM_COUNT
        jb      .sum                    ; loop while i < NUM_COUNT
        mov     [total], eax            ; store the result in memory
        int3                            ; CHECKPOINT 2  -> eax = 80 (50h)

; --- Checkpoint 3: copy a string byte by byte ------------------------------
        lea     rsi, [greeting]         ; source
        lea     rdi, [buffer]           ; destination
.copy:
        mov     al, [rsi]
        mov     [rdi], al
        inc     rsi
        inc     rdi
        test    al, al                  ; was it the terminating zero?
        jnz     .copy
        int3                            ; CHECKPOINT 3  -> da buffer

; --- Checkpoint 4: structure fields --------------------------------------
        mov     eax, [point.x]
        add     eax, [point.y]          ; 10 + 20
        mov     [point.x], eax          ; point.x = 30
        int3                            ; CHECKPOINT 4

; --- Checkpoint 5: a variable that changes (use a hardware watchpoint) -----
        mov     ecx, 5
.count:
        inc     qword [counter]         ; memory can be modified directly
        dec     ecx
        jnz     .count
        int3                            ; CHECKPOINT 5

; --- Checkpoint 6: the stack --------------------------------------------
        mov     rax, 1111h
        push    rax                     ; rsp -= 8; [rsp] = rax
        push    2222h                   ; immediates can be pushed too
        int3                            ; CHECKPOINT 6  -> dq @rsp L4
        pop     rbx                     ; rbx = 2222h; rsp += 8
        pop     rcx                     ; rcx = 1111h; rsp += 8

; --- Checkpoint 7: lea as a calculator ------------------------------------
        mov     rcx, 7
        lea     rax, [rcx + rcx*4]      ; rax = 7*5     = 35
        lea     rax, [rax*2 + 3]        ; rax = 35*2+3  = 73
        lea     rdx, [rcx - 1]          ; rdx = 6, without touching flags
        int3                            ; CHECKPOINT 7

        xor     ecx, ecx
        call    [ExitProcess]

; -----------------------------------------------------------------------------
section '.data' data readable writeable

magic           dq 1122334455667788h

numbers         dd 5, 12, -3, 40, 7, 19         ; six signed dwords
NUM_COUNT       = ($ - numbers) / 4             ; assemble-time constant: 6
total           dd 0

greeting        db 'Hello, memory!', 0

                align 8                         ; keep qwords 8-byte aligned
counter         dq 0

point:                                          ; a hand-made "struct"
  .x            dd 10                           ; label point.x
  .y            dd 20                           ; label point.y

buffer          rb 64                           ; 64 reserved (zeroed) bytes

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL'
        import  kernel32, ExitProcess, 'ExitProcess'
