; =============================================================================
; Lesson 13 - HTTP GET over a raw TCP socket
;
; Usage:   http_get.exe [host]          (default: example.com)
;
; Resolves the host name with getaddrinfo (DNS), connects to port 80, sends
; an HTTP/1.1 request and prints the raw response (headers + body).
;
; Build:   fasm http_get.asm
; Run:     http_get.exe example.com
; =============================================================================

format PE64 console
entry start

include 'win64a.inc'

BUF_SIZE = 4096

section '.text' code readable executable

start:
        sub     rsp, 8

        ; --- host name from the command line, or the default ---------------
        call    get_first_arg           ; rax -> argument or empty string
        cmp     byte [rax], 0
        je      .use_default
        mov     [host], rax
        jmp     .have_host
.use_default:
        lea     rax, [default_host]
        mov     [host], rax
.have_host:

        invoke  WSAStartup, 0202h, wsadata
        test    eax, eax
        jnz     fail

        ; --- 1. DNS: host name -> list of addresses -----------------------
        fastcall print_z, msg_resolving
        fastcall print_z, [host]
        fastcall print_nl
        invoke  getaddrinfo, [host], port_str, hints, ai_list
        test    eax, eax
        jnz     fail_gai                ; getaddrinfo returns the error code

        ; --- 2. try each address until one connects ----------------------
        mov     rbx, [ai_list]          ; rbx = current addrinfo
.try_next:
        test    rbx, rbx
        jz      fail                    ; ran out of addresses
        mov     ecx, [rbx + 4]          ; ai_family
        mov     edx, [rbx + 8]          ; ai_socktype
        mov     r8d, [rbx + 12]         ; ai_protocol
        invoke  socket, rcx, rdx, r8
        cmp     rax, INVALID_SOCKET
        je      .advance
        mov     [sock], rax
        mov     rdx, [rbx + 32]         ; ai_addr
        mov     r8, [rbx + 16]          ; ai_addrlen
        invoke  connect, [sock], rdx, r8
        test    eax, eax
        jz      .connected
        invoke  closesocket, [sock]
.advance:
        mov     rbx, [rbx + 40]         ; ai_next
        jmp     .try_next

.connected:
        invoke  freeaddrinfo, [ai_list]
        fastcall print_z, msg_connected

        ; --- 3. build and send the request --------------------------------
        ;   GET / HTTP/1.1\r\nHost: <host>\r\nConnection: close\r\n\r\n
        lea     rdi, [request]
        lea     rsi, [req_part1]
        call    append_z
        mov     rsi, [host]
        call    append_z
        lea     rsi, [req_part2]
        call    append_z
        lea     rax, [request]
        sub     rdi, rax
        mov     [request_len], rdi

        invoke  send, [sock], request, [request_len], 0
        cmp     eax, SOCKET_ERROR
        je      fail

        ; --- 4. print everything until the server closes the connection -----
.recv_loop:
        invoke  recv, [sock], buffer, BUF_SIZE, 0
        cmp     eax, 0
        jle     .finished
        mov     eax, eax
        mov     [received], rax
        add     [total], rax
        fastcall print_n, buffer, [received]
        jmp     .recv_loop

.finished:
        fastcall print_nl
        fastcall print_z, msg_total
        fastcall print_u64, [total]
        fastcall print_nl
        invoke  closesocket, [sock]
        invoke  WSACleanup
        invoke  ExitProcess, 0

fail_gai:
        mov     eax, eax
        mov     [last_error], rax
        jmp     report
fail:
        invoke  WSAGetLastError
        mov     [last_error], rax
report:
        fastcall print_z, msg_error
        fastcall print_u64, [last_error]
        fastcall print_nl
        invoke  ExitProcess, 1

; -----------------------------------------------------------------------------
; append_z: copy zero-terminated string at rsi to rdi (without the zero);
;           rdi is left pointing after the copied bytes.
; -----------------------------------------------------------------------------
append_z:
        mov     al, [rsi]
        test    al, al
        jz      .done
        mov     [rdi], al
        inc     rsi
        inc     rdi
        jmp     append_z
.done:
        ret

; -----------------------------------------------------------------------------
; get_first_arg() -> rax = pointer to first command-line argument ('' if none)
; (same logic as lesson 08)
; -----------------------------------------------------------------------------
proc get_first_arg
        invoke  GetCommandLineA
        cmp     byte [rax], '"'
        jne     .unquoted
        inc     rax
  .quoted:
        mov     cl, [rax]
        test    cl, cl
        jz      .done
        inc     rax
        cmp     cl, '"'
        jne     .quoted
        jmp     .skip
  .unquoted:
        mov     cl, [rax]
        test    cl, cl
        jz      .done
        cmp     cl, ' '
        je      .skip
        inc     rax
        jmp     .unquoted
  .skip:
        fastcall skip_spaces, rax
  .done:
        ret
endp

        include '..\common\console.inc'

; -----------------------------------------------------------------------------
section '.data' data readable writeable

default_host    db 'example.com', 0
port_str        db '80', 0

req_part1       db 'GET / HTTP/1.1', 13, 10, 'Host: ', 0
req_part2       db 13, 10, 'User-Agent: asm-http/1.0', 13, 10
                db 'Connection: close', 13, 10, 13, 10, 0

msg_resolving   db 'resolving ', 0
msg_connected   db 'connected, sending request...', 13, 10, 13, 10, 0
msg_total       db '--- bytes received: ', 0
msg_error       db 'error ', 0

                align 8
hints           dd 0                    ; ai_flags
                dd AF_UNSPEC            ; ai_family: IPv4 or IPv6, whatever works
                dd SOCK_STREAM          ; ai_socktype
                dd IPPROTO_TCP          ; ai_protocol
                dq 0, 0, 0, 0           ; addrlen, canonname, addr, next

host            dq ?
ai_list         dq ?
sock            dq ?
request_len     dq ?
received        dq ?
total           dq 0
last_error      dq ?
wsadata         rb 512
request         rb 1024
buffer          rb BUF_SIZE

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL', \
                ws2_32,   'WS2_32.DLL'

        include 'api\kernel32.inc'
        include '..\common\ws2_32.inc'
