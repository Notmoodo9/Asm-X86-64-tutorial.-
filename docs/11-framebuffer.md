# 11 — Your own pixels: framebuffer and Bresenham

Sources:
[`examples/common/framebuffer.inc`](../examples/common/framebuffer.inc),
[`examples/11-paint/paint.asm`](../examples/11-paint/paint.asm)

In lesson 10 Windows drew the lines. Now **you** draw them: you'll own an
array of pixels, implement the classic line-drawing algorithm yourself, and
only ask Windows to copy the finished image to the screen. This is how games,
emulators and demos render, and it's where assembly gets fun.

The result is a little paint program: drag to draw, right-click to change
colour, `C` to clear.

## A framebuffer is just memory

An 800×600 image with 32 bits per pixel is `800 × 600 × 4 = 1 920 000` bytes.
We get them from the OS:

```asm
invoke  VirtualAlloc, NULL, FB_W * FB_H * 4, MEM_COMMIT + MEM_RESERVE, PAGE_READWRITE
mov     [pixels], rax
```

Pixels are stored row after row ("row-major"). The pixel at (x, y) is at

```
address = pixels + (y * FB_W + x) * 4
```

```asm
        mov     eax, edx                ; y
        imul    eax, eax, FB_W          ; y * width
        add     eax, ecx                ; + x
        mov     [r9 + rax*4], r8d       ; store colour
```

Each pixel is a dword `0x00RRGGBB`. In memory (little-endian) that's the bytes
`BB GG RR 00` — the "BGRA" order Windows bitmaps use. Note this is **the
opposite of GDI's `COLORREF`** (`0x00BBGGRR`). Mixing the two up gives you blue
where you wanted red; you'll do it at least once.

### Bounds checking with one comparison per axis

```asm
        cmp     ecx, FB_W
        jae     .out
```

An *unsigned* comparison treats a negative `x` as a huge number, so this single
test rejects both `x < 0` and `x >= FB_W`. Never write outside your buffer —
the best case is an access violation; the worst case is silently corrupting
other data.

### Filling fast: `rep stosd`

```asm
        mov     eax, ecx                ; colour
        mov     rdi, [pixels]
        mov     ecx, FB_W * FB_H        ; count
        rep     stosd
```

`stosd` stores `eax` at `[rdi]` and advances `rdi` by 4; `rep` repeats it
`rcx` times. One instruction clears the whole screen. (`rdi` is non-volatile,
so `fb_clear` saves it.)

## Showing the framebuffer: `StretchDIBits`

```asm
  .paint:
        invoke  BeginPaint, [hwnd], ps
        mov     [hdc], rax
        invoke  StretchDIBits, [hdc], 0, 0, FB_W, FB_H, 0, 0, FB_W, FB_H, \
                               [pixels], bmi, DIB_RGB_COLORS, SRCCOPY
        invoke  EndPaint, [hwnd], ps
```

A **DIB** (device-independent bitmap) is "a pointer to pixels plus a header
that describes them". The header is a `BITMAPINFOHEADER` we lay out by hand:

```asm
bmi     dd 40           ; biSize
        dd FB_W         ; biWidth
        dd -FB_H        ; biHeight: negative = first row is the TOP row
        dw 1            ; biPlanes
        dw 32           ; biBitCount
        dd 0            ; biCompression = BI_RGB (uncompressed)
        dd 0, 0, 0, 0, 0
```

A positive height would mean "bottom-up" (row 0 at the bottom) — a leftover
from OS/2. Negative gives us the natural top-down layout.

`StretchDIBits` takes **13 arguments** — 4 in registers, 9 on the stack. With
`invoke` it's one line; by hand it would be nine `mov [rsp+...]`s.

The cycle for every change:

```
mouse message → draw into pixels → InvalidateRect → WM_PAINT → StretchDIBits
```

We also answer `WM_ERASEBKGND` with 1 ("already erased"), because we cover
every pixel anyway. Letting Windows erase first causes flicker.

## Bresenham's line algorithm

How do you draw a line from (x0, y0) to (x1, y1) with only integer
arithmetic? You step one pixel at a time and keep an **error term** that tracks
how far the ideal line has drifted from the pixel you're on.

The all-directions version (it's in `framebuffer.inc`):

```
dx =  |x1-x0|,  sx = x0<x1 ? 1 : -1
dy = -|y1-y0|,  sy = y0<y1 ? 1 : -1
err = dx + dy
loop:
    plot(x0, y0)
    if x0 == x1 and y0 == y1: break
    e2 = 2*err
    if e2 >= dy: err += dy; x0 += sx     // time to step in x
    if e2 <= dx: err += dx; y0 += sy     // time to step in y
```

```
  y
  0 ■ ■ ·  ·  ·  ·  ·
  1 · · ■  ■  ·  ·  ·      line from (0,0) to (6,3)
  2 · · ·  ·  ■  ■  ·      each step moves x, and sometimes y
  3 · · ·  ·  ·  ·  ■
    0 1 2  3  4  5  6  x
```

`err` is (scaled) "how much ahead of the line we are". Steps in x add `dy`
(negative); steps in y add `dx` (positive). Whichever direction reduces the
error the most gets taken — sometimes both (a diagonal step). No division, no
floating point: perfect for assembly, and how hardware drew lines for decades.

### Translating to registers

With 12 live values, a register plan comes first:

```
ecx x0      edx y0      r8d x1      r9d y1          (the arguments, in place)
r10d dx     r11d dy     ebx sx      esi sy
edi err     eax e2/tmp  r12d color  r13 pixels
```

`rbx rsi rdi r12 r13` are non-volatile, so `draw_line` pushes them (5 pushes)
and the 5th argument, `color`, moves from `[rsp+40]` to `[rsp+80]`:

```
 rsp+80  color (5th arg)          ┐ as the caller left it
 rsp+48  shadow space (32 bytes)  │
 rsp+40  return address           ┘
 rsp+32  saved rbx
 rsp+24  saved rsi
 rsp+16  saved rdi
 rsp+8   saved r12
 rsp+0   saved r13
```

The absolute value and sign come together neatly:

```asm
        mov     r10d, r8d
        sub     r10d, ecx               ; dx = x1 - x0   (sets flags)
        mov     ebx, 1                  ; sx = 1         (mov leaves flags alone)
        jge     .dx_ok
        neg     r10d                    ; dx = -dx
        neg     ebx                     ; sx = -1
.dx_ok:
```

And the two decisions:

```asm
.step:
        lea     eax, [rdi + rdi]        ; e2 = 2*err
        cmp     eax, r11d
        jl      .no_x                   ; signed! err and dy can be negative
        add     edi, r11d
        add     ecx, ebx
.no_x:
        cmp     eax, r10d
        jg      .no_y
        add     edi, r10d
        add     edx, esi
.no_y:
        jmp     .loop
```

Note `jl`/`jg` — **signed** comparisons, because the error term goes negative.
Using `jb`/`ja` here is a typical bug: the line would go off in a strange
direction. (Try it! It's a good debugging exercise.)

Clipping is done per pixel with the same unsigned trick as `fb_plot`, so lines
may start or end off-screen. (Real clipping — computing where the line enters
the screen — is an exercise.)

## Mouse handling

```asm
  .mousemove:
        test    qword [wparam], MK_LBUTTON      ; left button held?
        jz      .handled
        movsx   rax, word [lparam]              ; new x
        mov     [cur_x], rax
        movsx   rax, word [lparam + 2]          ; new y
        mov     [cur_y], rax
        fastcall draw_line, [last_x], [last_y], [cur_x], [cur_y], [color]
        ...  last = cur ...
        invoke  InvalidateRect, [hwnd], NULL, 0
```

Mouse-move messages arrive every few pixels, not every pixel — so we draw a
**line** from the previous position to the current one, which gives continuous
strokes. `SetCapture` on button-down keeps the messages coming even when the
mouse leaves the window (coordinates can then be negative — hence `movsx` and
clipping).

## Explore in WinDbg

```bat
cd examples\11-paint
fasm paint.asm
windbgx paint.exe
```

### See the framebuffer in memory

```
bp kernelbase!VirtualAlloc
g
gu
r rax
```

That's `pixels`. Let the program run (`g`), draw something, break in
(Ctrl+Break), and look at the memory:

```
dd <pixels> L20
```

White is `00ffffff`. The palette bar at the top shows the colour values. Find
the pixel at (100, 50):

```
dd <pixels> + (0n50 * 0n800 + 0n100) * 4 L1
```

### Draw from the debugger

Write pixels directly while the program is stopped:

```
f <pixels> + 0n200*0n800*4 L0n3200 00 00 ff 00
g
```

`f` fills memory with a byte pattern: here one full row of 800 pixels set to
`00 00 ff 00` = `0x00FF0000` = red... but nothing appears until the window
repaints! Drag another window over it, or draw a stroke. Your red line appears.
The framebuffer is just memory; `WM_PAINT` is what puts it on screen.

### Step through Bresenham

Find `draw_line` (the target of the `call` after the `fastcall` in the mouse
handler — or search for its first instructions `push rbx / push rsi / push rdi
/ push r12 / push r13`), then:

```
bp <draw_line>
g
```

Click once in the window (a single dot: x0=x1, y0=y1). Then step with `p` and
watch it plot one pixel and exit at the `je .done`. Now `bc *`, set it again,
and drag a short diagonal stroke. Step through the loop watching `ecx`, `edx`
(x, y) and `edi` (err):

```
r ecx, edx, edi
```

### A conditional breakpoint on the algorithm

Stop only if a line is longer than 100 pixels horizontally:

```
bp <draw_line> ".if (@r8d - @ecx > 0n100 & @r8d - @ecx < 0n10000) {} .else {gc}"
```

### Data breakpoint on a pixel

"Who wrote to this pixel?" — the question you'll ask when debugging graphics:

```
ba w4 <pixels> + (0n300 * 0n800 + 0n400) * 4
g
```

Draw across the centre of the window. WinDbg stops on the exact
`mov [r13+rax*4], r12d` that wrote it, inside `draw_line`, and `k` shows you it
came from `WindowProc`'s `WM_MOUSEMOVE` handler.

## Exercises

1. **Thick brush**: draw each line 3 times with y offset −1, 0, +1 (or write
   `draw_thick_line` that plots a 3×3 square per point).
2. **Click the palette**: if `WM_LBUTTONDOWN` happens with y < `PALETTE_SIZE`,
   pick the colour under the mouse (x / swatch width) instead of drawing.
3. **Rectangles and circles**: right-drag to draw a rectangle outline (four
   `draw_line`s). Then implement the midpoint circle algorithm — it's
   Bresenham's sibling.
4. **Flood fill** with a middle click: an explicit stack of (x, y) points in a
   `VirtualAlloc`'d buffer (recursion would overflow the stack).
5. **Save to BMP**: write a `BITMAPFILEHEADER` (14 bytes: `'BM'`, file size,
   0, offset 54) + your `bmi` header + the pixel array with `CreateFileA` /
   `WriteFile`. Open it in Paint. (Use positive height and write rows
   bottom-up, or check that your viewer accepts top-down BMPs.)
6. **Animation**: add `SetTimer(hwnd, 1, 16, NULL)` (~60 FPS) and on
   `WM_TIMER` draw a rotating line (use a sine table), `InvalidateRect`. No
   flicker, because the whole frame is copied in one go.
7. Break Bresenham on purpose: change `jl .no_x` to `jb .no_x`. Predict what
   happens, then confirm in the debugger.

Next: [12 — TCP networking with Winsock](12-sockets.md)
