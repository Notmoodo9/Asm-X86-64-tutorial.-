; =============================================================================
; Lesson 08 - wc: count lines, words and bytes in a file
;
; Usage:   wc.exe <filename>
;
; Demonstrates: GetCommandLineA parsing, CreateFileA, GetFileSizeEx,
; HeapAlloc/HeapFree, ReadFile, CloseHandle, error handling via GetLastError.
;
; Build:   fasm wc.asm
; Run:     wc.exe wc.asm
; =============================================================================

format PE64 console
entry start

include 'win64a.inc'

section '.text' code readable executable

start:
        sub     rsp, 8

        ; --- 1. find the first argument on the command line ----------------
        invoke  GetCommandLineA         ; e.g.  "C:\x\wc.exe"  file.txt
        mov     rsi, rax
        cmp     byte [rsi], '"'
        jne     .skip_unquoted
        inc     rsi                     ; quoted program name: skip to closing "
.skip_quoted:
        mov     al, [rsi]
        test    al, al
        jz      .usage
        inc     rsi
        cmp     al, '"'
        jne     .skip_quoted
        jmp     .after_name
.skip_unquoted:                         ; unquoted: skip to first space
        mov     al, [rsi]
        test    al, al
        jz      .usage
        cmp     al, ' '
        je      .after_name
        inc     rsi
        jmp     .skip_unquoted
.after_name:
        fastcall skip_spaces, rsi
        mov     [filename], rax
        cmp     byte [rax], 0
        je      .usage
        ; (filenames containing spaces would need quote handling here too -
        ;  that's an exercise)

        ; --- 2. open the file ---------------------------------------------
        invoke  CreateFileA, [filename], GENERIC_READ, FILE_SHARE_READ, NULL, \
                             OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL
        cmp     rax, INVALID_HANDLE_VALUE
        je      .error_open
        mov     [hfile], rax

        ; --- 3. how big is it? -------------------------------------------
        invoke  GetFileSizeEx, [hfile], filesize
        test    eax, eax
        jz      .error

        ; --- 4. allocate a buffer on the process heap ------------------------
        invoke  GetProcessHeap
        mov     [hheap], rax
        mov     r8, [filesize]
        inc     r8                      ; +1 so even an empty file gets a block
        ; NOT rcx: invoke loads rcx (1st arg) first, which would overwrite it
        invoke  HeapAlloc, [hheap], 0, r8
        test    rax, rax
        jz      .error
        mov     [buffer], rax

        ; --- 5. read the whole file ---------------------------------------
        invoke  ReadFile, [hfile], [buffer], [filesize], bytesread, NULL
        test    eax, eax
        jz      .error
        invoke  CloseHandle, [hfile]

        ; --- 6. count ------------------------------------------------------
        mov     rsi, [buffer]
        mov     ecx, [bytesread]        ; bytes left
        xor     r8d, r8d                ; lines
        xor     r9d, r9d                ; words
        xor     r10d, r10d              ; in_word flag
.scan:
        test    rcx, rcx
        jz      .counted
        mov     al, [rsi]
        cmp     al, 10                  ; LF ends a line
        jne     @f
        inc     r8
@@:
        cmp     al, ' '                 ; treat every byte <= ' ' as whitespace
        jbe     .space
        test    r10d, r10d
        jnz     .continue
        inc     r9                      ; first char of a new word
        mov     r10d, 1
        jmp     .continue
.space:
        xor     r10d, r10d
.continue:
        inc     rsi
        dec     rcx
        jmp     .scan
.counted:
        mov     [lines], r8
        mov     [words], r9

        ; --- 7. report -----------------------------------------------------
        fastcall print_z, str_lines
        fastcall print_u64, [lines]
        fastcall print_z, str_words
        fastcall print_u64, [words]
        fastcall print_z, str_bytes
        mov     eax, [bytesread]
        fastcall print_u64, rax
        fastcall print_z, str_sep
        fastcall print_z, [filename]
        fastcall print_nl

        invoke  HeapFree, [hheap], 0, [buffer]
        invoke  ExitProcess, 0

.usage:
        fastcall print_z, str_usage
        invoke  ExitProcess, 1

.error_open:
.error:
        invoke  GetLastError
        mov     [lasterr], rax
        fastcall print_z, str_error
        fastcall print_u64, [lasterr]
        fastcall print_nl
        invoke  ExitProcess, 2

        include '..\common\console.inc'

; -----------------------------------------------------------------------------
section '.data' data readable writeable

str_usage       db 'usage: wc <file>', 13, 10, 0
str_error       db 'error, GetLastError() = ', 0
str_lines       db 'lines: ', 0
str_words       db '  words: ', 0
str_bytes       db '  bytes: ', 0
str_sep         db '  ', 0

                align 8
filename        dq ?
hfile           dq ?
hheap           dq ?
buffer          dq ?
filesize        dq ?            ; LARGE_INTEGER (64-bit)
lines           dq ?
words           dq ?
lasterr         dq ?
bytesread       dd ?

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL'
        include 'api\kernel32.inc'
