# 10 — Drawing lines with GDI

Source: [`examples/10-gdi/gdi_lines.asm`](../examples/10-gdi/gdi_lines.asm)

You have a window. Now draw a line in it — then many lines, then shapes and
text — using **GDI** (Graphics Device Interface), the classic Windows 2D API
in `GDI32.DLL`.

What you'll see: a thick red line across the top, a fan of coloured lines
that together trace a curve, a rectangle, an ellipse and a caption.

## When do you draw? `WM_PAINT`

You don't draw whenever you like. Windows tells you **when your window needs
painting** — when it first appears, is uncovered, resized, restored — by
sending `WM_PAINT`. Your window procedure redraws everything then.

```asm
  .paint:
        invoke  BeginPaint, [hwnd], ps      ; -> rax = HDC
        mov     [hdc], rax
        ... draw with [hdc] ...
        invoke  EndPaint, [hwnd], ps
        xor     eax, eax
        ret
```

* `BeginPaint` returns a **device context** (`HDC`): a handle to a drawing
  surface plus drawing state (current pen, brush, font, colours, position).
* It fills in a `PAINTSTRUCT` — we reserve 72 bytes for it (`ps rb 72`) and
  just hand its address to `BeginPaint`/`EndPaint`.
* Every `BeginPaint` needs an `EndPaint`, or Windows keeps sending `WM_PAINT`
  forever (100% CPU — a classic bug).

To *request* a repaint yourself (because your data changed), call
`InvalidateRect(hwnd, NULL, FALSE)`. Windows will send `WM_PAINT` soon.

## Drawing a line

```asm
        invoke  CreatePen, PS_SOLID, 5, RGB_RED     ; style, width, colour
        mov     rsi, rax                            ; keep our pen
        invoke  SelectObject, [hdc], rsi            ; use it; returns the old pen
        mov     rdi, rax
        invoke  MoveToEx, [hdc], 20, 20, NULL       ; pen up at (20,20)
        invoke  LineTo, [hdc], 680, 20              ; pen down to (680,20)
        invoke  SelectObject, [hdc], rdi            ; restore the old pen
        invoke  DeleteObject, rsi                   ; free ours
```

GDI draws with "the currently selected objects". `SelectObject` swaps one in
and returns what was there before. The discipline is:

1. create the object
2. select it, saving the old one
3. draw
4. select the old one back
5. delete yours

Skipping 4–5 leaks **GDI objects** — a process is limited to 10 000 of them.
Leak one pen per `WM_PAINT` and your program eventually stops drawing.
(Task Manager → Details → add the "GDI objects" column to watch it.)

Coordinates are in pixels, relative to the window's **client area** (inside
the frame and title bar). (0,0) is the top left; y grows **downward**.

### Colours: `COLORREF`

```asm
RGB_RED   = 0x000000FF      ; 0x00BBGGRR
RGB_BLUE  = 0x00FF0000
```

GDI colours are `0x00BBGGRR` — red in the *lowest* byte. (Lesson 11's pixel
buffer is the opposite: `0x00RRGGBB`. Yes, really.)

## Drawing many lines: a loop around API calls

```asm
        xor     ebx, ebx                ; i = 0
  .art:
        ... compute colour into r8d ...
        invoke  CreatePen, PS_SOLID, 1, r8
        ...
        imul    eax, ebx, 20
        add     eax, 60                 ; y0 = 60 + 20i
        invoke  MoveToEx, [hdc], 40, rax, NULL
        imul    eax, ebx, 20
        add     eax, 40                 ; x1 = 40 + 20i
        invoke  LineTo, [hdc], rax, 400
        ...
        inc     ebx
        cmp     ebx, 17
        jb      .art
```

The loop counter lives in `rbx` because it must **survive the API calls** —
`rbx` is non-volatile. If you used `rcx` it would be destroyed by the first
`invoke` (and also overwritten by the first argument!). `rbx`, `rsi`, `rdi`
are pushed/popped by `proc ... uses rbx rsi rdi`, so the caller's values are
safe too.

Each line goes from a point on the left edge to a point on the bottom edge,
both moving by 20 pixels per step. Straight lines, but together they trace a
curve — the envelope is a parabola. That's "string art".

Also notice `invoke MoveToEx, [hdc], 40, rax, NULL`: computing an argument in
`rax` right before the call is fine because `invoke` loads `rcx`, `rdx`, then
`r8 ← rax` — `rax` isn't touched before that.

## Shapes and text

```asm
invoke  Rectangle, [hdc], 420, 80, 660, 220      ; outline with pen, fill with brush
invoke  Ellipse,   [hdc], 440, 250, 660, 400     ; ellipse inside that box
invoke  SetBkMode, [hdc], TRANSPARENT            ; text without a background box
invoke  TextOutA,  [hdc], 440, 430, label_text, label_len
```

`Rectangle` and `Ellipse` take 5 arguments (one on the stack) and fill with the
current **brush** (white by default). Try `GetStockObject(NULL_BRUSH)` to get
outlines only.

## Explore in WinDbg

```bat
cd examples\10-gdi
fasm gdi_lines.asm
windbgx gdi_lines.exe
```

### Watch every line being drawn

```
bp gdi32!LineTo ".printf \"LineTo(%d, %d)\\n\", @edx, @r8d; gc"
g
```

(If the breakpoint doesn't resolve, the real implementation may be in
`gdi32full`: use `x gdi32*!LineTo` to find it.)

Resize the window: each repaint prints all 18 `LineTo` calls again.

### Slow motion

GDI draws immediately to the window. So you can **watch a picture appear line
by line**: put the WinDbg window beside the program, and

```
bc *
bp gdi32!LineTo
g
```

then press `g` repeatedly (F5). Each press draws one more line. (Windows may
repaint the window while you're in the debugger, which restarts the
sequence — that's `WM_PAINT` in action.)

### Change what's drawn

At the `LineTo` breakpoint, rewrite the arguments before the line is drawn:

```
r edx = 0n700
r r8d = 0n0
g
```

The first line now goes somewhere else. You're editing the picture through the
calling convention.

### Find the leak

Comment out both `DeleteObject` calls, rebuild, and run it. Open Task Manager
→ **Details**, right-click the column header → *Select columns* → tick **GDI
objects**. Resize the window back and forth: the count for `gdi_lines.exe`
climbs by 18 with every repaint. Put the `DeleteObject` calls back and it stays
flat.

In WinDbg you can count calls instead:

```
r $t0 = 0
bp gdi32!CreatePen "r $t0 = @$t0 + 1; gc"
bp gdi32!DeleteObject "r $t0 = @$t0 - 1; gc"
g
```

Break in after a few resizes (Ctrl+Break) and `? @$t0` — zero if balanced.

## Exercises

1. **Clock face**: draw 12 tick marks around a circle. You'll need sine and
   cosine — easiest is a precomputed table of 12 (x, y) offsets in your data
   section (`dd 0,-100, 50,-87, 87,-50, 100,0, ...`).
2. **Grid**: draw a 10×10 grid with two loops. Use a nested loop with `rbx`
   and `rsi`/`r12` as counters.
3. **Follow the mouse**: store the last `WM_MOUSEMOVE` position (`0x200`) in
   variables, call `InvalidateRect`, and in `WM_PAINT` draw a line from the
   window centre to the mouse.
4. **Polyline**: GDI's `Polyline(hdc, points, count)` draws connected
   segments from an array of `POINT { dd x, y }`. Draw a zig-zag from a data
   table in one call.
5. Make the line pattern **animate**: `SetTimer` (lesson 09 exercise 6), and
   on `WM_TIMER` change an offset variable and `InvalidateRect`. You'll see
   flicker — lesson 11 shows how to avoid it.

Next: [11 — Your own pixels: framebuffer and Bresenham](11-framebuffer.md)
