; =============================================================================
; Lesson 09 - a real Win32 window
;
; Registers a window class, creates a window, runs the message loop, and
; handles a few messages in the window procedure:
;   left click  -> shows the click position in the title bar
;   Esc         -> closes the window
;
; Build:   fasm window.asm
; Run:     window.exe
; =============================================================================

format PE64 GUI 5.0                     ; GUI subsystem: no console window
entry start

include 'win64a.inc'

section '.text' code readable executable

start:
        sub     rsp, 8

        ; --- 1. fill in and register the window class ----------------------
        invoke  GetModuleHandleA, 0
        mov     [wc.hInstance], rax
        invoke  LoadIconA, 0, IDI_APPLICATION
        mov     [wc.hIcon], rax
        mov     [wc.hIconSm], rax
        invoke  LoadCursorA, 0, IDC_ARROW
        mov     [wc.hCursor], rax
        invoke  RegisterClassExA, wc
        test    rax, rax
        jz      error

        ; --- 2. create the window -------------------------------------------
        invoke  CreateWindowExA, 0, class_name, window_title, \
                                 WS_VISIBLE + WS_OVERLAPPEDWINDOW, \
                                 100, 100, 640, 480, \
                                 NULL, NULL, [wc.hInstance], NULL
        test    rax, rax
        jz      error
        mov     [main_hwnd], rax

        ; --- 3. the message loop ---------------------------------------------
msg_loop:
        invoke  GetMessageA, msg, NULL, 0, 0
        cmp     eax, 1
        jb      end_loop                ; 0 = WM_QUIT
        jne     msg_loop                ; -1 = error (ignore)
        invoke  TranslateMessage, msg   ; turns key presses into WM_CHAR
        invoke  DispatchMessageA, msg   ; calls our WindowProc
        jmp     msg_loop

error:
        invoke  MessageBoxA, NULL, error_text, NULL, MB_ICONERROR + MB_OK

end_loop:
        invoke  ExitProcess, [msg.wParam]

; -----------------------------------------------------------------------------
; WindowProc(hwnd, wmsg, wparam, lparam)
;
; Windows calls this for every message sent to our window. It must follow the
; calling convention exactly - it's called from inside user32.dll.
; -----------------------------------------------------------------------------
proc WindowProc uses rbx rsi rdi, hwnd, wmsg, wparam, lparam

        mov     [hwnd], rcx             ; store the register arguments in
        mov     [wmsg], rdx             ; their shadow slots so we can refer
        mov     [wparam], r8            ; to them by name
        mov     [lparam], r9

        cmp     edx, WM_LBUTTONDOWN
        je      .lbuttondown
        cmp     edx, WM_KEYDOWN
        je      .keydown
        cmp     edx, WM_DESTROY
        je      .destroy

  .default:                             ; everything we don't handle
        invoke  DefWindowProcA, [hwnd], [wmsg], [wparam], [lparam]
        ret

  .lbuttondown:
        ; lparam: low 16 bits = x, high 16 bits = y (signed, client coords)
        movsx   rsi, word [lparam]      ; x
        movsx   rdi, word [lparam + 2]  ; y
        invoke  wsprintfA, title_buf, click_fmt, rsi, rdi
        invoke  SetWindowTextA, [hwnd], title_buf
        xor     eax, eax                ; "handled" -> return 0
        ret

  .keydown:
        cmp     qword [wparam], VK_ESCAPE
        jne     .default
        invoke  DestroyWindow, [hwnd]
        xor     eax, eax
        ret

  .destroy:
        invoke  PostQuitMessage, 0      ; makes GetMessage return 0
        xor     eax, eax
        ret
endp

; -----------------------------------------------------------------------------
section '.data' data readable writeable

class_name      db 'AsmWindowClass', 0
window_title    db 'Hello, window! (click me, Esc quits)', 0
error_text      db 'Startup failed.', 0
click_fmt       db 'Clicked at x=%d, y=%d', 0

                align 8
wc              WNDCLASSEX sizeof.WNDCLASSEX, CS_HREDRAW + CS_VREDRAW, \
                           WindowProc, 0, 0, NULL, NULL, NULL, \
                           COLOR_WINDOW + 1, NULL, class_name, NULL
msg             MSG
main_hwnd       dq ?
title_buf       rb 128

; -----------------------------------------------------------------------------
section '.idata' import data readable writeable

        library kernel32, 'KERNEL32.DLL', \
                user32,   'USER32.DLL'

        include 'api\kernel32.inc'
        include 'api\user32.inc'
