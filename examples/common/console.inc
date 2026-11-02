; =============================================================================
; console.inc - a small console toolkit (built in lesson 07)
;
; Include it INSIDE your code section:
;
;     section '.text' code readable executable
;         ...
;         include '..\common\console.inc'
;
; Needs KERNEL32 imports (GetStdHandle, WriteFile, ReadFile) - include
; 'api\kernel32.inc' in your import section.
;
; Every routine follows the Windows x64 calling convention. Procs are only
; assembled if your program uses them.
;
;   print_n   (pbuf, nbytes)       write nbytes bytes
;   print_z   (pstr)               write a zero-terminated string
;   print_nl  ()                   write CR LF
;   print_u64 (value)              write an unsigned number in decimal
;   print_i64 (value)              write a signed number in decimal
;   print_hex (value)              write a 64-bit value as 16 hex digits
;   read_line (pbuf, maxlen) -> rax = length   (CR/LF stripped, zero added;
;                                                buffer must be maxlen+1 bytes)
;   parse_u64 (pstr) -> rax = value, rdx = pointer to first non-digit
;   parse_i64 (pstr) -> rax = value, rdx = pointer to first non-digit
;   skip_spaces(pstr) -> rax = pointer to first non-space character
; =============================================================================

proc print_n uses rbx, pbuf, nbytes
  locals
        nwritten dd ?
  endl
        mov     [pbuf], rcx
        mov     [nbytes], rdx
        invoke  GetStdHandle, STD_OUTPUT_HANDLE
        mov     rbx, rax                ; keep the handle out of rax: invoke
                                        ; below may use rax as a temporary
        invoke  WriteFile, rbx, [pbuf], [nbytes], addr nwritten, 0
        ret
endp

proc print_z uses rsi, pstr
        mov     rsi, rcx
        xor     edx, edx
  .len:
        cmp     byte [rsi + rdx], 0
        je      .print
        inc     rdx
        jmp     .len
  .print:
        fastcall print_n, rsi, rdx      ; rcx <- rsi, rdx already holds length
        ret
endp

proc print_nl
        fastcall print_n, console_crlf, 2
        ret
endp

proc print_u64 uses rbx rsi rdi, value
  locals
        digits  rb 32
  endl
        mov     rax, rcx
        lea     rdi, [digits + 31]      ; fill from the end of the buffer
        mov     ebx, 10
        xor     esi, esi                ; number of digits
  .next:
        xor     edx, edx
        div     rbx                     ; rax = rax/10, rdx = rax%10
        add     dl, '0'
        mov     [rdi], dl
        dec     rdi
        inc     rsi
        test    rax, rax
        jnz     .next
        inc     rdi                     ; rdi -> first digit
        fastcall print_n, rdi, rsi
        ret
endp

proc print_i64 uses rbx, value
        mov     rbx, rcx
        test    rbx, rbx
        jns     .positive
        fastcall print_n, console_minus, 1
        neg     rbx
  .positive:
        fastcall print_u64, rbx
        ret
endp

proc print_hex uses rbx rsi, value
  locals
        hexbuf  rb 16
  endl
        mov     rax, rcx
        lea     rsi, [hexbuf + 15]
        lea     r8, [console_hexdigits] ; RIP-relative addressing can't take an
                                        ; index register, so load the base first
        mov     ecx, 16
  .digit:
        mov     edx, eax
        and     edx, 0Fh                ; low nibble
        mov     dl, [r8 + rdx]
        mov     [rsi], dl
        dec     rsi
        shr     rax, 4
        dec     ecx
        jnz     .digit
        lea     rbx, [hexbuf]
        fastcall print_n, rbx, 16
        ret
endp

proc read_line uses rbx rsi, pbuf, maxlen
  locals
        nread   dd ?
  endl
        mov     [pbuf], rcx
        mov     [maxlen], rdx
        invoke  GetStdHandle, STD_INPUT_HANDLE
        mov     rbx, rax
        mov     [nread], 0
        invoke  ReadFile, rbx, [pbuf], [maxlen], addr nread, 0
        mov     eax, [nread]            ; zero-extends into rax
        mov     rsi, [pbuf]
  .strip:                               ; remove trailing CR / LF
        test    eax, eax
        jz      .done
        mov     cl, [rsi + rax - 1]
        cmp     cl, 13
        je      .cut
        cmp     cl, 10
        jne     .done
  .cut:
        dec     eax
        jmp     .strip
  .done:
        mov     byte [rsi + rax], 0     ; zero-terminate
        ret
endp

; parse_u64: a leaf function (calls nothing, uses only volatile registers),
; so it needs no prologue at all.
parse_u64:
        xor     eax, eax
  .next:
        movzx   edx, byte [rcx]
        sub     edx, '0'
        cmp     edx, 9
        ja      .done                   ; unsigned trick: catches < '0' and > '9'
        imul    rax, rax, 10
        add     rax, rdx
        inc     rcx
        jmp     .next
  .done:
        mov     rdx, rcx
        ret

parse_i64:
        cmp     byte [rcx], '-'
        jne     parse_u64               ; tail call: no sign
        inc     rcx
        sub     rsp, 40                 ; we call a function: align + shadow
        call    parse_u64
        add     rsp, 40
        neg     rax
        ret

skip_spaces:
        mov     rax, rcx
  .loop:
        cmp     byte [rax], ' '
        je      .skip
        cmp     byte [rax], 9           ; tab
        jne     .done
  .skip:
        inc     rax
        jmp     .loop
  .done:
        ret

; read-only data used by the routines above. Kept in the code section so the
; include is self-contained (code sections are readable).
console_crlf      db 13, 10
console_minus     db '-'
console_hexdigits db '0123456789ABCDEF'
