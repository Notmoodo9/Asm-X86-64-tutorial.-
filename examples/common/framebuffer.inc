; =============================================================================
; framebuffer.inc - software rendering into a 32-bit pixel buffer (lesson 11)
;
; Include it INSIDE your code section. Your program must define:
;
;     FB_W = <width>            ; constants: buffer size in pixels
;     FB_H = <height>
;     pixels dq ?               ; pointer to FB_W*FB_H dwords (0x00RRGGBB)
;
; Routines (Windows x64 calling convention; all are leaf functions):
;
;   fb_clear (color)
;   fb_plot  (x, y, color)                  ignores pixels outside the buffer
;   draw_line(x0, y0, x1, y1, color)        Bresenham, all octants, clipped
;   fb_fill_rect(x, y, w, h, color)         clipped
; =============================================================================

; -----------------------------------------------------------------------------
; fb_clear(ecx = color)
; -----------------------------------------------------------------------------
fb_clear:
        push    rdi                     ; rdi is non-volatile: save it
        mov     eax, ecx
        mov     rdi, [pixels]
        mov     ecx, FB_W * FB_H
        rep     stosd                   ; while (rcx--) { [rdi] = eax; rdi += 4 }
        pop     rdi
        ret

; -----------------------------------------------------------------------------
; fb_plot(ecx = x, edx = y, r8d = color)
; -----------------------------------------------------------------------------
fb_plot:
        cmp     ecx, FB_W               ; unsigned compare: negative x becomes
        jae     .out                    ; huge and fails too - one test, two bounds
        cmp     edx, FB_H
        jae     .out
        mov     eax, edx
        imul    eax, eax, FB_W          ; y * width
        add     eax, ecx                ; + x
        mov     r9, [pixels]
        mov     [r9 + rax*4], r8d       ; 4 bytes per pixel
  .out:
        ret

; -----------------------------------------------------------------------------
; draw_line(ecx = x0, edx = y0, r8d = x1, r9d = y1, [rsp+40] = color)
;
; Bresenham's line algorithm, integer-only, works in every direction:
;
;     dx =  |x1-x0|,  sx = x0<x1 ? 1 : -1
;     dy = -|y1-y0|,  sy = y0<y1 ? 1 : -1
;     err = dx + dy
;     loop:
;         plot(x0, y0)
;         if x0 == x1 and y0 == y1: break
;         e2 = 2*err
;         if e2 >= dy: err += dy; x0 += sx
;         if e2 <= dx: err += dx; y0 += sy
;
; Register plan:
;   ecx x0      edx y0      r8d x1      r9d y1
;   r10d dx     r11d dy     ebx sx      esi sy
;   edi err     eax e2/tmp  r12d color  r13 pixels
; -----------------------------------------------------------------------------
draw_line:
        push    rbx
        push    rsi
        push    rdi
        push    r12
        push    r13
        ; 5 pushes = 40 bytes. At entry the 5th argument was at [rsp+40]
        ; (above the return address and 32 bytes of shadow space); now it's
        ; at [rsp + 40 + 40].
        mov     r12d, [rsp + 80]
        mov     r13, [pixels]

        mov     r10d, r8d
        sub     r10d, ecx               ; dx = x1 - x0
        mov     ebx, 1                  ; sx = 1   (mov doesn't change flags)
        jge     .dx_ok
        neg     r10d                    ; dx = |dx|
        neg     ebx                     ; sx = -1
  .dx_ok:
        mov     r11d, r9d
        sub     r11d, edx               ; dy = y1 - y0
        mov     esi, 1
        jge     .dy_ok
        neg     r11d
        neg     esi
  .dy_ok:
        neg     r11d                    ; dy = -|y1 - y0|
        lea     edi, [r10 + r11]        ; err = dx + dy

  .loop:
        ; plot (x0, y0) if inside the buffer
        cmp     ecx, FB_W
        jae     .skip
        cmp     edx, FB_H
        jae     .skip
        mov     eax, edx
        imul    eax, eax, FB_W
        add     eax, ecx
        mov     [r13 + rax*4], r12d
  .skip:
        cmp     ecx, r8d
        jne     .step
        cmp     edx, r9d
        je      .done
  .step:
        lea     eax, [rdi + rdi]        ; e2 = 2*err
        cmp     eax, r11d
        jl      .no_x                   ; if e2 >= dy:
        add     edi, r11d               ;     err += dy
        add     ecx, ebx                ;     x0  += sx
  .no_x:
        cmp     eax, r10d
        jg      .no_y                   ; if e2 <= dx:
        add     edi, r10d               ;     err += dx
        add     edx, esi                ;     y0  += sy
  .no_y:
        jmp     .loop

  .done:
        pop     r13
        pop     r12
        pop     rdi
        pop     rsi
        pop     rbx
        ret

; -----------------------------------------------------------------------------
; fb_fill_rect(ecx = x, edx = y, r8d = w, r9d = h, [rsp+40] = color)
; -----------------------------------------------------------------------------
fb_fill_rect:
        push    rbx
        push    rsi
        push    rdi
        mov     r11d, [rsp + 40 + 24]   ; color (3 pushes = 24 bytes)
        ; clip: x0 = max(x,0), x1 = min(x+w, FB_W), same for y
        lea     r10d, [rcx + r8]        ; x1 = x + w
        lea     r9d, [rdx + r9]         ; y1 = y + h
        test    ecx, ecx
        jns     @f
        xor     ecx, ecx
    @@: test    edx, edx
        jns     @f
        xor     edx, edx
    @@: cmp     r10d, FB_W
        jle     @f
        mov     r10d, FB_W
    @@: cmp     r9d, FB_H
        jle     @f
        mov     r9d, FB_H
    @@:
        mov     rsi, [pixels]
        mov     eax, r11d               ; color for stosd
  .row:
        cmp     edx, r9d
        jge     .done
        mov     ebx, r10d
        sub     ebx, ecx                ; pixels in this row
        jle     .done
        mov     edi, edx
        imul    edi, edi, FB_W
        add     edi, ecx                ; index of first pixel
        lea     rdi, [rsi + rdi*4]
        mov     r8d, ecx                ; save x0 (rep stosd uses rcx)
        mov     ecx, ebx
        rep     stosd
        mov     ecx, r8d
        inc     edx
        jmp     .row
  .done:
        pop     rdi
        pop     rsi
        pop     rbx
        ret
