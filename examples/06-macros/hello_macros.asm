; =============================================================================
; Lesson 06 - the same kind of program as lesson 05, written with FASM's
; Windows macros: invoke, fastcall, proc/endp, locals, library/import.
;
; Build:   fasm hello_macros.asm
; Run:     hello_macros.exe
; =============================================================================

format PE64 console
entry start

include 'win64a.inc'

section '.text' code readable executable

start:
        sub     rsp, 8                  ; align the stack ONCE: 8 + 8 = 16.
                                        ; invoke reserves shadow space itself.

        invoke  GetStdHandle, STD_OUTPUT_HANDLE
        mov     [hstdout], rax

        invoke  WriteFile, [hstdout], message, message_len, written, 0

        ; our own procedure, called with the same argument-passing rules
        fastcall greet, name1, 3
        fastcall greet, name2, 1

        invoke  MessageBoxA, NULL, mb_text, mb_caption, MB_OK
        invoke  ExitProcess, 0

; -----------------------------------------------------------------------------
; greet(name, times)  - prints "Hello, <name>!" <times> times
; -----------------------------------------------------------------------------
proc greet uses rbx rsi, pname, times

  locals
        len     dq ?
  endl

        ; Arguments ARRIVE IN REGISTERS. 'pname' and 'times' name the caller's
        ; shadow-space slots at [rbp+16] and [rbp+24]; proc does not copy them
        ; there - do it yourself if you want to use the names.
        mov     [pname], rcx
        mov     [times], rdx

        ; strlen(pname) -> len
        mov     rsi, rcx
        xor     eax, eax
  .strlen:
        cmp     byte [rsi + rax], 0
        je      .gotlen
        inc     rax
        jmp     .strlen
  .gotlen:
        mov     [len], rax

        mov     rbx, [times]
  .again:
        invoke  WriteFile, [hstdout], hello_part, hello_len, written, 0
        invoke  WriteFile, [hstdout], [pname], [len], written, 0
        invoke  WriteFile, [hstdout], bang_part, bang_len, written, 0
        dec     rbx
        jnz     .again
        ret                             ; 'ret' inside proc emits the epilogue
endp

; -----------------------------------------------------------------------------
section '.data' data readable writeable

hstdout         dq ?
written         dd ?

message         db 'Same program, now with macros.', 13, 10
message_len     = $ - message

hello_part      db 'Hello, '
hello_len       = $ - hello_part
bang_part       db '!', 13, 10
bang_len        = $ - bang_part

name1           db 'FASM', 0
name2           db 'WinDbg', 0

mb_text         db 'invoke placed these arguments for me.', 0
mb_caption      db 'hello_macros', 0

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL', \
                user32,   'USER32.DLL'

        include 'api\kernel32.inc'      ; declares ALL kernel32 functions;
        include 'api\user32.inc'        ; only the ones you use are imported
