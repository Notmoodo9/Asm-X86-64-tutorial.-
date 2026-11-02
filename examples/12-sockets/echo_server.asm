; =============================================================================
; Lesson 12 - a TCP echo server
;
; Listens on port 5000. For each client: prints what it receives and sends
; it straight back. Handles one client at a time.
;
; Build:   fasm echo_server.asm
; Run:     echo_server.exe
; Test:    echo_client.exe   (or: telnet localhost 5000 / ncat localhost 5000)
; =============================================================================

format PE64 console
entry start

include 'win64a.inc'

PORT     = 5000
BUF_SIZE = 1024

section '.text' code readable executable

start:
        sub     rsp, 8

        ; --- 1. initialise Winsock (version 2.2) -----------------------------
        invoke  WSAStartup, 0202h, wsadata
        test    eax, eax
        jnz     fail

        ; --- 2. create a TCP socket ----------------------------------------
        invoke  socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
        cmp     rax, INVALID_SOCKET
        je      fail
        mov     [listen_sock], rax

        ; --- 3. bind it to 0.0.0.0:5000 -------------------------------------
        invoke  bind, [listen_sock], listen_addr, 16
        test    eax, eax
        jnz     fail

        ; --- 4. start listening -------------------------------------------
        invoke  listen, [listen_sock], 5
        test    eax, eax
        jnz     fail
        fastcall print_z, msg_listening

        ; --- 5. accept clients forever -----------------------------------
accept_loop:
        invoke  accept, [listen_sock], NULL, NULL
        cmp     rax, INVALID_SOCKET
        je      fail
        mov     [client_sock], rax
        fastcall print_z, msg_connected

recv_loop:
        invoke  recv, [client_sock], buffer, BUF_SIZE, 0
        cmp     eax, 0
        jle     client_gone             ; 0 = closed politely, -1 = error
        mov     eax, eax                ; zero-extend the int into rax
        mov     [received], rax

        fastcall print_z, msg_got
        fastcall print_n, buffer, [received]
        fastcall print_nl

        invoke  send, [client_sock], buffer, [received], 0
        cmp     eax, SOCKET_ERROR
        je      client_gone
        jmp     recv_loop

client_gone:
        invoke  closesocket, [client_sock]
        fastcall print_z, msg_disconnected
        jmp     accept_loop

fail:
        invoke  WSAGetLastError
        mov     [last_error], rax
        fastcall print_z, msg_error
        fastcall print_u64, [last_error]
        fastcall print_nl
        invoke  WSACleanup
        invoke  ExitProcess, 1

        include '..\common\console.inc'

; -----------------------------------------------------------------------------
section '.data' data readable writeable

; sockaddr_in for 0.0.0.0:PORT  ("any local address")
                align 4
listen_addr     dw AF_INET
                db PORT shr 8, PORT and 0FFh    ; port, big-endian (network order)
                db 0, 0, 0, 0                   ; INADDR_ANY
                rb 8                            ; sin_zero

msg_listening   db 'echo server listening on port 5000', 13, 10, 0
msg_connected   db '[client connected]', 13, 10, 0
msg_disconnected db '[client disconnected]', 13, 10, 0
msg_got         db 'received: ', 0
msg_error       db 'socket error ', 0

                align 8
listen_sock     dq ?
client_sock     dq ?
received        dq ?
last_error      dq ?
wsadata         rb 512
buffer          rb BUF_SIZE

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL', \
                ws2_32,   'WS2_32.DLL'

        include 'api\kernel32.inc'
        include '..\common\ws2_32.inc'
