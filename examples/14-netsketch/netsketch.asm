; =============================================================================
; Lesson 14 - NetSketch: a shared whiteboard over TCP
;
; Start it twice. The first instance can't connect to anyone, so it becomes
; the host and waits; the second connects to it. Everything either one draws
; appears on both.
;
;   left drag     draw            right click   next colour
;   C             clear (local)   Esc           quit
;
; To use two computers: set PEER_IP below to the host's address on the
; machine that should connect, and allow the program through the firewall.
;
; Architecture:
;
;   GUI thread                               network thread (net_thread)
;   ----------                               ---------------------------
;   message loop                             connect() or listen()/accept()
;   WM_MOUSEMOVE: draw_line locally,         loop:
;                 send 16-byte packet ------>    recv_all 16 bytes
;   WM_NETLINE:   draw_line from packet <----    PostMessage(WM_NETLINE)
;   WM_NETSTATUS: update title bar      <----    PostMessage(WM_NETSTATUS)
;
; Packet format (16 bytes, little-endian):
;   +0 dw x0   +2 dw y0   +4 dw x1   +6 dw y1   +8 dq color (0x00RRGGBB)
;
; Build:   fasm netsketch.asm
; =============================================================================

format PE64 GUI 5.0
entry start

include 'win64a.inc'

FB_W         = 800
FB_H         = 600
PORT         = 5050
PACKET_SIZE  = 16

WM_NETLINE   = 8000h + 1        ; WM_APP + 1: a line arrived from the peer
WM_NETSTATUS = 8000h + 2        ; WM_APP + 2: wparam = pointer to new title

WINDOW_STYLE = WS_VISIBLE + WS_OVERLAPPED + WS_CAPTION + WS_SYSMENU + WS_MINIMIZEBOX

macro PEER_IP { db 127, 0, 0, 1 }       ; <- change to the host's IP address

section '.text' code readable executable

start:
        sub     rsp, 8

        invoke  WSAStartup, 0202h, wsadata
        test    eax, eax
        jnz     error

        invoke  VirtualAlloc, NULL, FB_W * FB_H * 4, MEM_COMMIT + MEM_RESERVE, PAGE_READWRITE
        test    rax, rax
        jz      error
        mov     [pixels], rax
        fastcall fb_clear, 0FFFFFFh

        invoke  GetModuleHandleA, 0
        mov     [wc.hInstance], rax
        invoke  LoadCursorA, 0, IDC_CROSS
        mov     [wc.hCursor], rax
        invoke  RegisterClassExA, wc
        test    rax, rax
        jz      error

        invoke  AdjustWindowRect, client_rect, WINDOW_STYLE, 0
        mov     eax, [client_rect + 8]
        sub     eax, [client_rect]
        mov     [win_w], rax
        mov     eax, [client_rect + 12]
        sub     eax, [client_rect + 4]
        mov     [win_h], rax

        invoke  CreateWindowExA, 0, class_name, title_starting, WINDOW_STYLE, \
                                 100, 100, [win_w], [win_h], \
                                 NULL, NULL, [wc.hInstance], NULL
        test    rax, rax
        jz      error
        mov     [main_hwnd], rax

        ; the window exists, so the network thread may now post messages to it
        invoke  CreateThread, NULL, 0, net_thread, NULL, 0, NULL
        test    rax, rax
        jz      error
        invoke  CloseHandle, rax        ; we don't need the thread handle

msg_loop:
        invoke  GetMessageA, msg, NULL, 0, 0
        cmp     eax, 1
        jb      end_loop
        jne     msg_loop
        invoke  TranslateMessage, msg
        invoke  DispatchMessageA, msg
        jmp     msg_loop

error:
        invoke  MessageBoxA, NULL, error_text, NULL, MB_ICONERROR + MB_OK
end_loop:
        invoke  ExitProcess, [msg.wParam]       ; also ends the network thread

; =============================================================================
; Network thread
; =============================================================================

; DWORD WINAPI net_thread(LPVOID param)  - a thread is just a function
proc net_thread uses rbx, param

        ; --- try to be a client ------------------------------------------
        invoke  socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
        cmp     rax, INVALID_SOCKET
        je      .offline
        mov     rbx, rax
        invoke  connect, rbx, peer_addr, 16
        test    eax, eax
        jnz     .become_host
        mov     [sock], rbx
        mov     [connected], 1
        invoke  PostMessageA, [main_hwnd], WM_NETSTATUS, title_client, 0
        jmp     .receive

        ; --- nobody there: be the host -----------------------------------
  .become_host:
        invoke  closesocket, rbx
        invoke  PostMessageA, [main_hwnd], WM_NETSTATUS, title_waiting, 0
        invoke  socket, AF_INET, SOCK_STREAM, IPPROTO_TCP
        cmp     rax, INVALID_SOCKET
        je      .offline
        mov     rbx, rax
        invoke  bind, rbx, listen_addr, 16
        test    eax, eax
        jnz     .offline_close
        invoke  listen, rbx, 1
        test    eax, eax
        jnz     .offline_close
        invoke  accept, rbx, NULL, NULL         ; blocks until a peer connects
        cmp     rax, INVALID_SOCKET
        je      .offline_close
        mov     [sock], rax
        mov     [connected], 1
        invoke  closesocket, rbx                ; stop listening: one peer only
        invoke  PostMessageA, [main_hwnd], WM_NETSTATUS, title_host, 0

        ; --- forward every packet to the GUI thread -----------------------
  .receive:
        fastcall recv_all, [sock], in_packet, PACKET_SIZE
        test    eax, eax
        jz      .disconnected
        ; the whole packet fits in the two message parameters
        invoke  PostMessageA, [main_hwnd], WM_NETLINE, [in_packet], [in_packet + 8]
        jmp     .receive

  .disconnected:
        mov     [connected], 0
        invoke  closesocket, [sock]
        invoke  PostMessageA, [main_hwnd], WM_NETSTATUS, title_disconnected, 0
        xor     eax, eax
        ret

  .offline_close:
        invoke  closesocket, rbx
  .offline:
        invoke  PostMessageA, [main_hwnd], WM_NETSTATUS, title_offline, 0
        xor     eax, eax
        ret
endp

; recv_all(sock, buffer, count) -> rax = 1 if all bytes arrived, 0 on close/error
proc recv_all uses rbx rsi rdi, s, pbuf, count
        mov     rbx, rcx                ; socket
        mov     rsi, rdx                ; where the next bytes go
        mov     rdi, r8                 ; bytes still missing
  .more:
        test    rdi, rdi
        jz      .ok
        invoke  recv, rbx, rsi, rdi, 0
        cmp     eax, 0
        jle     .fail
        mov     eax, eax
        add     rsi, rax
        sub     rdi, rax
        jmp     .more
  .ok:
        mov     eax, 1
        ret
  .fail:
        xor     eax, eax
        ret
endp

; =============================================================================
; GUI thread
; =============================================================================

; local_stroke() - draw [last_x,last_y]->[cur_x,cur_y] here and on the peer
proc local_stroke
        fastcall draw_line, [last_x], [last_y], [cur_x], [cur_y], [color]

        cmp     [connected], 0
        je      .redraw
        mov     ax, word [last_x]       ; pack the packet: 4 x 16-bit coords
        mov     word [out_packet], ax
        mov     ax, word [last_y]
        mov     word [out_packet + 2], ax
        mov     ax, word [cur_x]
        mov     word [out_packet + 4], ax
        mov     ax, word [cur_y]
        mov     word [out_packet + 6], ax
        mov     rax, [color]
        mov     [out_packet + 8], rax
        ; a 16-byte send on a blocking socket sends all 16 bytes (or fails)
        invoke  send, [sock], out_packet, PACKET_SIZE, 0
  .redraw:
        invoke  InvalidateRect, [main_hwnd], NULL, 0
        ret
endp

proc WindowProc uses rbx rsi rdi, hwnd, wmsg, wparam, lparam
        mov     [hwnd], rcx
        mov     [wmsg], rdx
        mov     [wparam], r8
        mov     [lparam], r9

        cmp     edx, WM_PAINT
        je      .paint
        cmp     edx, WM_ERASEBKGND
        je      .erasebkgnd
        cmp     edx, WM_LBUTTONDOWN
        je      .lbuttondown
        cmp     edx, WM_MOUSEMOVE
        je      .mousemove
        cmp     edx, WM_LBUTTONUP
        je      .lbuttonup
        cmp     edx, WM_RBUTTONDOWN
        je      .rbuttondown
        cmp     edx, WM_KEYDOWN
        je      .keydown
        cmp     edx, WM_NETLINE
        je      .netline
        cmp     edx, WM_NETSTATUS
        je      .netstatus
        cmp     edx, WM_DESTROY
        je      .destroy
  .default:
        invoke  DefWindowProcA, [hwnd], [wmsg], [wparam], [lparam]
        ret

  .paint:
        invoke  BeginPaint, [hwnd], ps
        mov     [hdc], rax
        invoke  StretchDIBits, [hdc], 0, 0, FB_W, FB_H, 0, 0, FB_W, FB_H, \
                               [pixels], bmi, DIB_RGB_COLORS, SRCCOPY
        invoke  EndPaint, [hwnd], ps
        jmp     .handled

  .erasebkgnd:
        mov     eax, 1
        ret

  .lbuttondown:
        invoke  SetCapture, [hwnd]
        movsx   rax, word [lparam]
        mov     [last_x], rax
        mov     [cur_x], rax
        movsx   rax, word [lparam + 2]
        mov     [last_y], rax
        mov     [cur_y], rax
        call    local_stroke            ; a dot
        jmp     .handled

  .mousemove:
        test    qword [wparam], MK_LBUTTON
        jz      .handled
        movsx   rax, word [lparam]
        mov     [cur_x], rax
        movsx   rax, word [lparam + 2]
        mov     [cur_y], rax
        call    local_stroke
        mov     rax, [cur_x]
        mov     [last_x], rax
        mov     rax, [cur_y]
        mov     [last_y], rax
        jmp     .handled

  .lbuttonup:
        invoke  ReleaseCapture
        jmp     .handled

  .rbuttondown:
        mov     rax, [color_index]
        inc     rax
        cmp     rax, NUM_COLORS
        jb      @f
        xor     eax, eax
    @@: mov     [color_index], rax
        lea     rcx, [palette]
        mov     ecx, [rcx + rax*4]
        mov     [color], rcx
        jmp     .handled

  .keydown:
        cmp     qword [wparam], VK_ESCAPE
        je      .escape
        cmp     qword [wparam], 'C'
        jne     .default
        fastcall fb_clear, 0FFFFFFh
        invoke  InvalidateRect, [hwnd], NULL, 0
        jmp     .handled
  .escape:
        invoke  DestroyWindow, [hwnd]
        jmp     .handled

  .netline:
        ; unpack: wparam = 4 signed 16-bit coordinates, lparam = colour
        movsx   rax, word [wparam]
        mov     [net_x0], rax
        movsx   rax, word [wparam + 2]
        mov     [net_y0], rax
        movsx   rax, word [wparam + 4]
        mov     [net_x1], rax
        movsx   rax, word [wparam + 6]
        mov     [net_y1], rax
        fastcall draw_line, [net_x0], [net_y0], [net_x1], [net_y1], [lparam]
        invoke  InvalidateRect, [hwnd], NULL, 0
        jmp     .handled

  .netstatus:
        invoke  SetWindowTextA, [hwnd], [wparam]
        jmp     .handled

  .destroy:
        invoke  PostQuitMessage, 0
  .handled:
        xor     eax, eax
        ret
endp

        include '..\common\framebuffer.inc'

; -----------------------------------------------------------------------------
section '.data' data readable writeable

class_name         db 'AsmNetSketch', 0
error_text         db 'Startup failed.', 0
title_starting     db 'NetSketch - starting...', 0
title_waiting      db 'NetSketch - hosting on port 5050, waiting for a peer...', 0
title_host         db 'NetSketch - peer connected (you are the host)', 0
title_client       db 'NetSketch - connected to host', 0
title_disconnected db 'NetSketch - peer disconnected (drawing locally)', 0
title_offline      db 'NetSketch - network unavailable (drawing locally)', 0

                align 4
peer_addr       dw AF_INET
                db PORT shr 8, PORT and 0FFh
                PEER_IP
                rb 8

listen_addr     dw AF_INET
                db PORT shr 8, PORT and 0FFh
                db 0, 0, 0, 0
                rb 8

palette         dd 0x000000, 0xE03030, 0x30A030, 0x3050E0, 0xF0A000, 0x9030C0
NUM_COLORS      = ($ - palette) / 4

bmi             dd 40, FB_W, -FB_H
                dw 1, 32
                dd 0, 0, 0, 0, 0, 0

client_rect     dd 0, 0, FB_W, FB_H

                align 8
wc              WNDCLASSEX sizeof.WNDCLASSEX, 0, WindowProc, 0, 0, NULL, NULL, \
                           NULL, NULL, NULL, class_name, NULL
msg             MSG

main_hwnd       dq ?
pixels          dq ?
hdc             dq ?
win_w           dq ?
win_h           dq ?
sock            dq ?
connected       dq 0            ; written by the network thread, read by the GUI
color           dq 0
color_index     dq 0
last_x          dq ?
last_y          dq ?
cur_x           dq ?
cur_y           dq ?
net_x0          dq ?
net_y0          dq ?
net_x1          dq ?
net_y1          dq ?
in_packet       rq 2            ; used only by the network thread
out_packet      rq 2            ; used only by the GUI thread
wsadata         rb 512
ps              rb 72

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL', \
                user32,   'USER32.DLL', \
                gdi32,    'GDI32.DLL', \
                ws2_32,   'WS2_32.DLL'

        include 'api\kernel32.inc'
        include 'api\user32.inc'
        include 'api\gdi32.inc'
        include '..\common\ws2_32.inc'
