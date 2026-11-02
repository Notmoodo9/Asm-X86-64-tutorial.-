; =============================================================================
; Lesson 12 - a TCP echo client
;
; Connects to 127.0.0.1:5000, sends each line you type, prints the reply.
; Empty line quits.
;
; Build:   fasm echo_client.asm
; Run:     (start echo_server.exe first)  echo_client.exe
; =============================================================================

format PE64 console
entry start

include 'win64a.inc'

PORT     = 5000
LINE_MAX = 255
BUF_SIZE = 1024

section '.text' code readable executable

start:
        sub     rsp, 8

        invoke  WSAStartup, 0202h, wsadata
        test    eax, eax
        jnz     fail

        invoke  socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
        cmp     rax, INVALID_SOCKET
        je      fail
        mov     [sock], rax

        ; connect() blocks until the TCP handshake completes (or fails)
        invoke  connect, [sock], server_addr, 16
        test    eax, eax
        jnz     fail
        fastcall print_z, msg_connected

chat:
        fastcall print_z, prompt
        fastcall read_line, line, LINE_MAX
        test    rax, rax
        jz      done
        mov     [line_len], rax

        invoke  send, [sock], line, [line_len], 0
        cmp     eax, SOCKET_ERROR
        je      fail

        ; TCP is a byte STREAM: one recv may return less than was sent.
        ; Keep reading until we have the whole echo back.
        mov     [got], 0
.more:
        lea     rdx, [reply]
        add     rdx, [got]              ; where to put the next bytes
        mov     r8, [line_len]
        sub     r8, [got]               ; how many we still expect
        invoke  recv, [sock], rdx, r8, 0
        cmp     eax, 0
        jle     server_gone
        mov     eax, eax
        add     [got], rax
        mov     rax, [got]
        cmp     rax, [line_len]
        jb      .more

        fastcall print_z, msg_reply
        fastcall print_n, reply, [got]
        fastcall print_nl
        jmp     chat

server_gone:
        fastcall print_z, msg_server_gone
done:
        invoke  shutdown, [sock], SD_BOTH
        invoke  closesocket, [sock]
        invoke  WSACleanup
        invoke  ExitProcess, 0

fail:
        invoke  WSAGetLastError
        mov     [last_error], rax
        fastcall print_z, msg_error
        fastcall print_u64, [last_error]
        fastcall print_nl
        invoke  ExitProcess, 1

        include '..\common\console.inc'

; -----------------------------------------------------------------------------
section '.data' data readable writeable

; sockaddr_in for 127.0.0.1:PORT
                align 4
server_addr     dw AF_INET
                db PORT shr 8, PORT and 0FFh    ; big-endian port
                db 127, 0, 0, 1                 ; IPv4 address, byte by byte
                rb 8

msg_connected   db 'connected to 127.0.0.1:5000 - type lines, empty line quits', 13, 10, 0
prompt          db '> ', 0
msg_reply       db 'echo: ', 0
msg_server_gone db 'server closed the connection', 13, 10, 0
msg_error       db 'socket error ', 0

                align 8
sock            dq ?
line_len        dq ?
got             dq ?
last_error      dq ?
wsadata         rb 512
line            rb LINE_MAX + 1
reply           rb BUF_SIZE

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL', \
                ws2_32,   'WS2_32.DLL'

        include 'api\kernel32.inc'
        include '..\common\ws2_32.inc'
