; =============================================================================
; Lesson 11 - a paint program with its own framebuffer and line algorithm
;
; Every pixel is ours: we keep an 800x600 array of 32-bit pixels in memory,
; draw into it with our own Bresenham line routine, and hand the finished
; image to Windows with StretchDIBits in WM_PAINT.
;
;   left drag     draw
;   right click   next colour
;   C             clear
;   Esc           quit
;
; Build:   fasm paint.asm
; Run:     paint.exe
; =============================================================================

format PE64 GUI 5.0
entry start

include 'win64a.inc'

FB_W = 800
FB_H = 600
PALETTE_SIZE = 16               ; height of the colour bar at the top

WINDOW_STYLE = WS_VISIBLE + WS_OVERLAPPED + WS_CAPTION + WS_SYSMENU + WS_MINIMIZEBOX

section '.text' code readable executable

start:
        sub     rsp, 8

        ; --- the framebuffer: FB_W*FB_H*4 bytes straight from the OS -----------
        invoke  VirtualAlloc, NULL, FB_W * FB_H * 4, MEM_COMMIT + MEM_RESERVE, PAGE_READWRITE
        test    rax, rax
        jz      error
        mov     [pixels], rax
        call    clear_canvas

        ; --- window class -----------------------------------------------------
        invoke  GetModuleHandleA, 0
        mov     [wc.hInstance], rax
        invoke  LoadCursorA, 0, IDC_CROSS
        mov     [wc.hCursor], rax
        invoke  RegisterClassExA, wc
        test    rax, rax
        jz      error

        ; --- size the window so the CLIENT area is exactly FB_W x FB_H ----------
        invoke  AdjustWindowRect, client_rect, WINDOW_STYLE, 0
        mov     eax, [client_rect + 8]          ; right
        sub     eax, [client_rect]              ; - left
        mov     [win_w], rax
        mov     eax, [client_rect + 12]         ; bottom
        sub     eax, [client_rect + 4]          ; - top
        mov     [win_h], rax

        invoke  CreateWindowExA, 0, class_name, title_default, WINDOW_STYLE, \
                                 100, 100, [win_w], [win_h], \
                                 NULL, NULL, [wc.hInstance], NULL
        test    rax, rax
        jz      error

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
        invoke  ExitProcess, [msg.wParam]

; -----------------------------------------------------------------------------
; clear_canvas() - white background plus a bar showing the palette
; -----------------------------------------------------------------------------
proc clear_canvas uses rbx rsi
        fastcall fb_clear, 0FFFFFFh
        xor     ebx, ebx                ; i = 0
  .swatch:
        lea     rax, [palette]
        mov     esi, [rax + rbx*4]      ; colour i  (not in rax: fastcall may
                                        ; use rax to store stack arguments)
        imul    ecx, ebx, FB_W / NUM_COLORS     ; x = i * swatch width
        fastcall fb_fill_rect, rcx, 0, FB_W / NUM_COLORS, PALETTE_SIZE, rsi
        inc     ebx
        cmp     ebx, NUM_COLORS
        jb      .swatch
        ret
endp

; -----------------------------------------------------------------------------
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
        cmp     edx, WM_DESTROY
        je      .destroy
  .default:
        invoke  DefWindowProcA, [hwnd], [wmsg], [wparam], [lparam]
        ret

  .paint:
        invoke  BeginPaint, [hwnd], ps
        mov     [hdc], rax
        ; copy our pixel array to the window in one call (13 arguments!)
        invoke  StretchDIBits, [hdc], \
                0, 0, FB_W, FB_H, \             ; destination rectangle
                0, 0, FB_W, FB_H, \             ; source rectangle
                [pixels], bmi, DIB_RGB_COLORS, SRCCOPY
        invoke  EndPaint, [hwnd], ps
        xor     eax, eax
        ret

  .erasebkgnd:
        mov     eax, 1                  ; "done" - we paint every pixel anyway,
        ret                             ; so skip erasing (prevents flicker)

  .lbuttondown:
        invoke  SetCapture, [hwnd]      ; keep getting mouse moves outside the window
        movsx   rax, word [lparam]
        mov     [last_x], rax
        movsx   rax, word [lparam + 2]
        mov     [last_y], rax
        ; a zero-length line = a single dot
        fastcall draw_line, [last_x], [last_y], [last_x], [last_y], [color]
        invoke  InvalidateRect, [hwnd], NULL, 0
        xor     eax, eax
        ret

  .mousemove:
        test    qword [wparam], MK_LBUTTON      ; is the left button held?
        jz      .handled
        movsx   rax, word [lparam]
        mov     [cur_x], rax
        movsx   rax, word [lparam + 2]
        mov     [cur_y], rax
        fastcall draw_line, [last_x], [last_y], [cur_x], [cur_y], [color]
        mov     rax, [cur_x]
        mov     [last_x], rax
        mov     rax, [cur_y]
        mov     [last_y], rax
        invoke  InvalidateRect, [hwnd], NULL, 0
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
        lea     rcx, [color_names]
        mov     rdx, [rcx + rax*8]      ; pointer to the colour's name
        invoke  SetWindowTextA, [hwnd], rdx
        jmp     .handled

  .keydown:
        cmp     qword [wparam], VK_ESCAPE
        je      .escape
        cmp     qword [wparam], 'C'     ; virtual-key code of C is its ASCII
        jne     .default
        call    clear_canvas
        invoke  InvalidateRect, [hwnd], NULL, 0
        jmp     .handled
  .escape:
        invoke  DestroyWindow, [hwnd]
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

class_name      db 'AsmPaint', 0
title_default   db 'asm paint - drag to draw, right-click: colour, C: clear', 0
error_text      db 'Startup failed.', 0

; pixel format 0x00RRGGBB (blue in the LOWEST byte - the reverse of COLORREF)
                align 4
palette         dd 0x000000, 0xE03030, 0x30A030, 0x3050E0, 0xF0A000, 0x9030C0, 0x00B0C0, 0xFFFFFF
NUM_COLORS      = ($ - palette) / 4

                align 8
color_names     dq name0, name1, name2, name3, name4, name5, name6, name7
name0           db 'black', 0
name1           db 'red', 0
name2           db 'green', 0
name3           db 'blue', 0
name4           db 'orange', 0
name5           db 'purple', 0
name6           db 'cyan', 0
name7           db 'white (eraser)', 0

                align 8
; BITMAPINFOHEADER: describes our pixel array to GDI
bmi             dd 40                   ; biSize
                dd FB_W                 ; biWidth
                dd -FB_H                ; biHeight: NEGATIVE = top-down rows
                dw 1                    ; biPlanes
                dw 32                   ; biBitCount
                dd 0                    ; biCompression = BI_RGB
                dd 0, 0, 0, 0, 0        ; size, x/y pixels per metre, colours

client_rect     dd 0, 0, FB_W, FB_H     ; RECT left, top, right, bottom

wc              WNDCLASSEX sizeof.WNDCLASSEX, 0, WindowProc, 0, 0, NULL, NULL, \
                           NULL, NULL, NULL, class_name, NULL
msg             MSG

pixels          dq ?
hdc             dq ?
win_w           dq ?
win_h           dq ?
color           dq 0x000000
color_index     dq 0
last_x          dq ?
last_y          dq ?
cur_x           dq ?
cur_y           dq ?
ps              rb 72                   ; PAINTSTRUCT

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL', \
                user32,   'USER32.DLL', \
                gdi32,    'GDI32.DLL'

        include 'api\kernel32.inc'
        include 'api\user32.inc'
        include 'api\gdi32.inc'
