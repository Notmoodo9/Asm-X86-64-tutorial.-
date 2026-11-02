# 09 — Opening a window

Source: [`examples/09-window/window.asm`](../examples/09-window/window.asm)

Time for graphics. Before you can draw anything you need a **window**, and
Windows GUI programs have a very particular shape. Once you understand it,
every GUI program — in any language — makes more sense, because they all sit on
top of exactly this.

## The shape of a GUI program

```
           ┌────────────────────────────┐
 start ──► │ RegisterClassExA(&wc)      │  "a kind of window, whose messages
           │   wc.lpfnWndProc = WindowProc     go to WindowProc"
           ├────────────────────────────┤
           │ CreateWindowExA(...)       │  an actual window of that class
           ├────────────────────────────┤
           │ loop:                      │
           │   GetMessageA(&msg)  ◄─────┼──── input, paint requests, timers...
           │   TranslateMessage(&msg)   │
           │   DispatchMessageA(&msg) ──┼──► WindowProc(hwnd, msg, wParam, lParam)
           └────────────────────────────┘           │
                                                    ├ WM_LBUTTONDOWN → our code
                                                    ├ WM_PAINT       → draw (lesson 10)
                                                    ├ WM_DESTROY     → PostQuitMessage
                                                    └ anything else  → DefWindowProcA
```

Your program doesn't *poll* the mouse. Windows queues **messages** for your
thread; your loop pulls them and hands them back to Windows, which calls your
**window procedure**. Your code runs in response to events.

`format PE64 GUI 5.0` sets the GUI subsystem (no console appears) and minimum
OS version 5.0.

## The window class

```asm
wc  WNDCLASSEX sizeof.WNDCLASSEX, CS_HREDRAW + CS_VREDRAW, \
               WindowProc, 0, 0, NULL, NULL, NULL, \
               COLOR_WINDOW + 1, NULL, class_name, NULL
```

`WNDCLASSEX` is a **structure** defined in FASM's includes (with the `struct`
macro). Instantiating it like this lays out the fields in memory with initial
values, and creates labels for each field: `wc.hInstance`, `wc.hCursor`, ...
`sizeof.WNDCLASSEX` is its size (80 bytes).

The equivalent C:

```c
typedef struct {
    UINT      cbSize;          // +0
    UINT      style;           // +4
    WNDPROC   lpfnWndProc;     // +8   <- our function pointer
    int       cbClsExtra;      // +16
    int       cbWndExtra;      // +20
    HINSTANCE hInstance;       // +24
    HICON     hIcon;           // +32
    HCURSOR   hCursor;         // +40
    HBRUSH    hbrBackground;   // +48
    LPCSTR    lpszMenuName;    // +56
    LPCSTR    lpszClassName;   // +64
    HICON     hIconSm;         // +72
} WNDCLASSEXA;                 // 80 bytes
```

Note the padding: pointers are 8-byte aligned, so after two 4-byte `int`s the
next pointer starts at +24. Struct layouts in x64 follow these alignment rules
— when you define your own Windows structs by hand, get them right.

## The window procedure

```asm
proc WindowProc uses rbx rsi rdi, hwnd, wmsg, wparam, lparam
```

Windows calls `WindowProc` with four arguments in `rcx`, `rdx`, `r8`, `r9`:
the window, the message number, and two message-specific parameters. It must
return a value in `rax` (usually 0 for "handled").

Things that make window procedures different from your other functions:

* **They're called by Windows, from inside `user32.dll`.** If you corrupt a
  non-volatile register or misalign the stack, the crash happens *later*, in
  Windows' code. `proc ... uses rbx rsi rdi` makes the save/restore automatic.
* **Unhandled messages must go to `DefWindowProcA`**, which implements all the
  default behaviour: moving, resizing, closing, painting the frame...
* **Re-entrancy.** Some API calls you make *from* the window procedure cause
  Windows to call the window procedure again (e.g. `DestroyWindow` sends
  `WM_DESTROY` while you're still handling `WM_KEYDOWN`). Don't keep important
  state only in volatile registers across API calls.

### Message parameters

For mouse messages, `lParam` packs the coordinates: low 16 bits = x, high 16
bits = y, both **signed** (negative when the mouse is captured and leaves the
window). Since the parameters were saved to memory, picking the halves is easy:

```asm
movsx   rsi, word [lparam]      ; x  (sign-extended)
movsx   rdi, word [lparam + 2]  ; y  (little-endian: bytes 2..3 are the high word)
```

### `wsprintfA`: calling a varargs function

```asm
invoke  wsprintfA, title_buf, click_fmt, rsi, rdi
```

`wsprintfA(buffer, format, ...)` is like C's `sprintf`. In the x64 convention
varargs functions are called exactly like normal ones (with one twist for
floating-point args, which must be duplicated in integer registers). Note: the
output buffer must be large enough — `wsprintfA` will write up to 1024 bytes.

## Explore in WinDbg

```bat
cd examples\09-window
fasm window.asm
windbgx window.exe
```

### Find the window procedure without symbols

The class registration tells us where `WindowProc` is:

```
bp user32!RegisterClassExA
g
dq @rcx L10
dq @rcx+8 L1
u poi(@rcx+8)
```

`rcx` points to our `wc`; at offset 8 is `lpfnWndProc`. Now set a breakpoint
**on it**, but use a condition so you only stop on clicks
(`WM_LBUTTONDOWN = 0x201`):

```
bp poi(@rcx+8) ".if (@edx == 0x201) { .echo CLICK; ? @r9 & 0xffff; ? @r9 >> 0n16 } .else { gc }"
g
```

Click in the window. WinDbg stops and prints x and y. Look at the call stack —
this is the interesting part:

```
k
```

```
 # Child-SP          RetAddr               Call Site
00 ...               USER32!UserCallWinProcCheckWow+0x2bd     window+0x1080
01 ...               USER32!DispatchMessageWorker+0x2a2        USER32!UserCallWinProcCheckWow+0x2bd
02 ...               window+0x1063                              USER32!DispatchMessageWorker+0x2a2
03 ...               KERNEL32!BaseThreadInitThunk+0x14          window+0x1063
...
```

Read it bottom-up: thread start → our `start` (`window+0x1063`, the message
loop) → `DispatchMessageWorker` → our `WindowProc`. You can *see* the message
loop calling you back.

### Message tracing

Log every message (careful — lots of output; mouse moves alone are many):

```
bc *
bp <WindowProc address> ".printf \"msg %04x wp %p lp %p\\n\", @edx, @r8, @r9; gc"
g
```

Move the mouse, resize, minimise. Look up the numbers in `WinUser.h` or
FASM's `INCLUDE\EQUATES\USER64.INC` (e.g. `0x200` WM_MOUSEMOVE, `0x0f`
WM_PAINT, `0x24` WM_GETMINMAXINFO, `0x84` WM_NCHITTEST).

Notice which messages arrive **without** going through `DispatchMessageA`
(look at `k` when one hits): those are *sent* directly by Windows, not *posted*
to the queue — e.g. `WM_CREATE` during `CreateWindowExA`.

### Look inside a queued message

`GetMessageA` fills our `msg` structure (`MSG`: `hwnd` +0, `message` +8,
`wParam` +16, `lParam` +24, `time` +32, `pt` +36). Catch one:

```
bc *
bp user32!GetMessageA
g
r $t0 = @rcx       ; remember the MSG pointer
gu                 ; let GetMessageA return
dd @$t0+8 L1       ; message number
dq @$t0+0x10 L2    ; wParam, lParam
```

Only *posted* messages (input, timers, `WM_PAINT`, `WM_QUIT`) come through
here. Repeat a few times while moving the mouse over the window.

> **Why not put `gu` inside the breakpoint's command string?** Commands after
> an execution command (`g`, `gu`, `p`, `t`) in a breakpoint command string
> don't run when you expect them to — execution has already resumed. Do it
> by hand as above, or use two breakpoints (one on the function, one on the
> return address).

## Exercises

1. Handle `WM_RBUTTONDOWN` (`0x204`): show a `MessageBoxA` with the
   coordinates. Pass `[hwnd]` as the owner so the box is modal.
2. Handle `WM_CHAR` (`0x102`): `wParam` is the character. Append typed
   characters to the title.
3. Handle `WM_SIZE` (`0x5`): `lParam` holds the new client width/height. Show
   them in the title.
4. Ask before closing: handle `WM_CLOSE` (`0x10`) with an `MB_YESNO` box; only
   call `DestroyWindow` if the answer is `IDYES` (6).
5. Change the background with `wc.hbrBackground`: `COLOR_BTNFACE + 1`, or
   create a brush: `invoke CreateSolidBrush, 0x00FF8000` (needs GDI32 — see
   lesson 10 for importing it).
6. Set a timer: `invoke SetTimer, [hwnd], 1, 1000, NULL` in the click handler,
   then handle `WM_TIMER` (`0x113`) to update a counter in the title once per
   second.

Next: [10 — Drawing lines with GDI](10-gdi.md)
