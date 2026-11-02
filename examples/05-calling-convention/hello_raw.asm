; =============================================================================
; Lesson 05 - the Windows x64 calling convention, by hand
;
; Prints a line to the console with WriteFile (5 arguments: one goes on the
; stack), then shows a MessageBox (4 arguments). No macros except the import
; table ones - every argument is placed manually.
;
; Build:   fasm hello_raw.asm
; Run:     hello_raw.exe
; Debug:   windbgx hello_raw.exe
; =============================================================================

format PE64 console
entry start

include 'win64a.inc'

section '.text' code readable executable

start:
        ; On entry, rsp is 8 mod 16 (a return address was just pushed).
        ; Reserve:  32 bytes shadow space  [rsp+0  .. rsp+31]
        ;           8  bytes 5th argument  [rsp+32]
        ;           8  bytes local 'written' [rsp+40]
        ;           8  bytes padding       [rsp+48]   -> keeps rsp 16-aligned
        sub     rsp, 56

        ; HANDLE h = GetStdHandle(STD_OUTPUT_HANDLE)
        mov     ecx, STD_OUTPUT_HANDLE          ; -11
        call    [GetStdHandle]                  ; result in rax

        ; WriteFile(h, message, message_len, &written, NULL)
        mov     rcx, rax                        ; 1st: handle
        lea     rdx, [message]                  ; 2nd: buffer
        mov     r8d, message_len                ; 3rd: number of bytes
        lea     r9, [rsp + 40]                  ; 4th: pointer to our local
        mov     qword [rsp + 32], 0             ; 5th: lpOverlapped = NULL
        call    [WriteFile]

        ; print how many bytes were written, using our own helper
        mov     ecx, [rsp + 40]                 ; 'written' (a DWORD)
        call    print_number

        ; MessageBoxA(NULL, text, caption, MB_OK | MB_ICONINFORMATION)
        xor     ecx, ecx
        lea     rdx, [mb_text]
        lea     r8, [mb_caption]
        mov     r9d, MB_OK + MB_ICONINFORMATION
        call    [MessageBoxA]

        ; ExitProcess(0)
        xor     ecx, ecx
        call    [ExitProcess]

; -----------------------------------------------------------------------------
; print_number(rcx = unsigned value)
; Writes the value in decimal plus CR LF to the console.
;
; A complete, by-the-book Windows x64 function with a frame pointer:
;   - saves the non-volatile registers it uses
;   - allocates locals + shadow space + outgoing args, keeping rsp aligned
; -----------------------------------------------------------------------------
print_number:
        push    rbp                     ; rsp: 8 mod 16  -> 0 mod 16
        mov     rbp, rsp                ; rbp = frame base (fixed from now on)
        push    rbx                     ; -> 8 mod 16
        push    rdi                     ; -> 0 mod 16
        sub     rsp, 32 + 16 + 32       ; shadow+arg5 (+pad) / written / digits
                                        ; = 80 -> still 0 mod 16
        ; frame layout (relative to rbp):
        ;   rbp+8    return address
        ;   rbp+0    saved rbp
        ;   rbp-8    saved rbx
        ;   rbp-16   saved rdi
        ;   rbp-48 .. rbp-17   digits buffer (32 bytes, filled from the end)
        ;   rbp-56   'written' local
        ;   rbp-96 .. rbp-57   outgoing: shadow (32) + 5th arg (8) = rsp..rsp+39

        ; convert: divide by 10 repeatedly, store digits right-to-left
        mov     rax, rcx
        lea     rdi, [rbp - 17]         ; last byte of the digit buffer
        mov     byte [rdi], 10          ; LF
        dec     rdi
        mov     byte [rdi], 13          ; CR
        mov     ebx, 10
.digit:
        xor     edx, edx
        div     rbx                     ; rax = rax / 10, rdx = rax % 10
        add     dl, '0'
        dec     rdi
        mov     [rdi], dl
        test    rax, rax
        jnz     .digit

        ; WriteFile(GetStdHandle(STD_OUTPUT_HANDLE), rdi, length, &written, 0)
        mov     ecx, STD_OUTPUT_HANDLE
        call    [GetStdHandle]
        mov     rcx, rax
        mov     rdx, rdi
        lea     r8, [rbp - 16]          ; one past the end of the buffer
        sub     r8, rdi                 ; length = end - start
        lea     r9, [rbp - 56]
        mov     qword [rsp + 32], 0
        call    [WriteFile]

        lea     rsp, [rbp - 16]         ; drop locals: rsp points at saved rdi
        pop     rdi
        pop     rbx
        pop     rbp
        ret

; -----------------------------------------------------------------------------
section '.data' data readable writeable

message         db 'Hello from hand-written x64 assembly!', 13, 10
message_len     = $ - message

mb_text         db 'Every argument of this call was placed by hand.', 0
mb_caption      db 'hello_raw', 0

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL', \
                user32,   'USER32.DLL'

        import  kernel32, \
                GetStdHandle, 'GetStdHandle', \
                WriteFile,    'WriteFile', \
                ExitProcess,  'ExitProcess'

        import  user32, \
                MessageBoxA,  'MessageBoxA'
