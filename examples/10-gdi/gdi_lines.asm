; =============================================================================
; Lesson 10 - drawing lines (and friends) with GDI
;
; In WM_PAINT this draws:
;   1. one thick red line
;   2. "string art": 17 lines in a loop, each with its own colour
;   3. a rectangle, an ellipse and some text
;
; Build:   fasm gdi_lines.asm
; Run:     gdi_lines.exe
; =============================================================================

format PE64 GUI 5.0
entry start

include 'win64a.inc'

; COLORREF is 0x00BBGGRR  (red in the LOW byte)
RGB_RED   = 0x000000FF
RGB_GREEN = 0x0000A000
RGB_BLUE  = 0x00FF0000
RGB_BLACK = 0x00000000

section '.text' code readable executable

start:
        sub     rsp, 8
        invoke  GetModuleHandleA, 0
        mov     [wc.hInstance], rax
        invoke  LoadCursorA, 0, IDC_ARROW
        mov     [wc.hCursor], rax
        invoke  RegisterClassExA, wc
        test    rax, rax
        jz      error
        invoke  CreateWindowExA, 0, class_name, window_title, \
                                 WS_VISIBLE + WS_OVERLAPPEDWINDOW, \
                                 100, 100, 720, 520, \
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
proc WindowProc uses rbx rsi rdi, hwnd, wmsg, wparam, lparam
        mov     [hwnd], rcx
        mov     [wmsg], rdx
        mov     [wparam], r8
        mov     [lparam], r9

        cmp     edx, WM_PAINT
        je      .paint
        cmp     edx, WM_DESTROY
        je      .destroy
  .default:
        invoke  DefWindowProcA, [hwnd], [wmsg], [wparam], [lparam]
        ret

  .paint:
        ; BeginPaint gives us a device context (HDC) - "something to draw on"
        invoke  BeginPaint, [hwnd], ps
        mov     [hdc], rax

        ; ---- 1. a single thick red line ------------------------------------
        invoke  CreatePen, PS_SOLID, 5, RGB_RED
        mov     rsi, rax                ; rsi = our pen
        invoke  SelectObject, [hdc], rsi
        mov     rdi, rax                ; rdi = the pen that was selected before
        invoke  MoveToEx, [hdc], 20, 20, NULL   ; set the "current position"
        invoke  LineTo, [hdc], 680, 20          ; line from there to here
        invoke  SelectObject, [hdc], rdi        ; ALWAYS restore the old object
        invoke  DeleteObject, rsi               ; then free ours

        ; ---- 2. string art: line i goes from (40, 60+20i) to (40+20i, 400) -
        xor     ebx, ebx                ; i = 0  (rbx survives API calls)
  .art:
        ; colour: blue grows with i, red shrinks
        mov     eax, ebx
        shl     eax, 4                  ; i*16   (0..256)
        cmp     eax, 255
        jbe     @f
        mov     eax, 255
    @@:
        mov     r8d, eax
        shl     r8d, 16                 ; blue byte
        mov     ecx, 255
        sub     ecx, eax
        or      r8d, ecx                ; red byte
        invoke  CreatePen, PS_SOLID, 1, r8      ; r8 is already the 3rd arg
        mov     rsi, rax
        invoke  SelectObject, [hdc], rsi
        mov     rdi, rax

        imul    eax, ebx, 20
        add     eax, 60                 ; y0 = 60 + 20i
        invoke  MoveToEx, [hdc], 40, rax, NULL
        imul    eax, ebx, 20
        add     eax, 40                 ; x1 = 40 + 20i
        invoke  LineTo, [hdc], rax, 400

        invoke  SelectObject, [hdc], rdi
        invoke  DeleteObject, rsi
        inc     ebx
        cmp     ebx, 17
        jb      .art

        ; ---- 3. shapes with a green pen, text in black --------------------
        invoke  CreatePen, PS_SOLID, 3, RGB_GREEN
        mov     rsi, rax
        invoke  SelectObject, [hdc], rsi
        mov     rdi, rax
        invoke  Rectangle, [hdc], 420, 80, 660, 220     ; left, top, right, bottom
        invoke  Ellipse, [hdc], 440, 250, 660, 400
        invoke  SelectObject, [hdc], rdi
        invoke  DeleteObject, rsi

        invoke  SetBkMode, [hdc], TRANSPARENT
        invoke  SetTextColor, [hdc], RGB_BLACK
        invoke  TextOutA, [hdc], 440, 430, label_text, label_len

        invoke  EndPaint, [hwnd], ps
        xor     eax, eax
        ret

  .destroy:
        invoke  PostQuitMessage, 0
        xor     eax, eax
        ret
endp

; -----------------------------------------------------------------------------
section '.data' data readable writeable

class_name      db 'AsmGdiLines', 0
window_title    db 'GDI lines', 0
error_text      db 'Startup failed.', 0
label_text      db 'Drawn with GDI from assembly'
label_len       = $ - label_text

                align 8
wc              WNDCLASSEX sizeof.WNDCLASSEX, CS_HREDRAW + CS_VREDRAW, \
                           WindowProc, 0, 0, NULL, NULL, NULL, \
                           COLOR_WINDOW + 1, NULL, class_name, NULL
msg             MSG
hdc             dq ?
ps              rb 72           ; PAINTSTRUCT (72 bytes on x64) - we only need
                                ; to pass its address to Begin/EndPaint

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL', \
                user32,   'USER32.DLL', \
                gdi32,    'GDI32.DLL'

        include 'api\kernel32.inc'
        include 'api\user32.inc'
        include 'api\gdi32.inc'
