# 15 — Where to go next

You can now write, structure and debug real Windows programs in assembly —
console tools, file utilities, GUI apps with your own renderer, and networked
programs. Here are directions to explore on your own, roughly from easiest to
most ambitious, with the APIs and concepts you'll need.

## Projects

### Games
* **Snake / Tetris-like / Breakout** on the lesson 11 framebuffer.
  `SetTimer` for the game tick, `WM_KEYDOWN` for input, `fb_fill_rect` for
  blocks. Add `GetTickCount64` for timing and a simple random number generator
  (xorshift: three shifts and three xors — perfect for asm).
* **Sprite blitting**: copy rectangles of pixels with a transparency colour;
  then **alpha blending** (per-channel `(a*src + (255-a)*dst) / 255`) — and
  then do it 4 pixels at a time with SSE2 (`punpcklbw`, `pmullw`, `psrlw`,
  `packuswb`).
* **Fixed-point 3D**: a rotating wireframe cube using `draw_line` and a sine
  table in 16.16 fixed point. Then switch to `float` with SSE (`movss`,
  `mulss`, `cvtss2si`) — remember float args go in `xmm0`–`xmm3`.

### Graphics
* **Mandelbrot set** with SSE2 doubles (`mulsd`, `addsd`, `comisd`), then
  vectorised with `mulpd` (2 pixels at once) or AVX `vmulpd` (4 at once).
  Time it with `QueryPerformanceCounter` — it's the classic "is asm faster?"
  experiment.
* **Fonts**: render text into your framebuffer by drawing with GDI into a
  DIB section (`CreateDIBSection` gives you a pixel pointer *and* an HBITMAP
  you can select into a memory DC).
* **OpenGL** via `opengl32.dll` (`wglCreateContext`...) — FASM ships an
  OpenGL example in `EXAMPLES\WIN64\OPENGL`. Or **Direct3D 11** — COM
  interfaces are tables of function pointers: `mov rax, [rcx]` /
  `call [rax + 8*n]`. Understanding COM vtables from assembly is a great way to
  finally understand COM.

### Systems
* **Processes**: `CreateProcessA`, pipes (`CreatePipe`), and write a tiny
  shell that runs commands and captures their output.
* **Memory-mapped files**: `CreateFileMappingA` + `MapViewOfFile` — open a
  1 GB file as if it were an array.
* **A PE parser**: open an `.exe`, follow `e_lfanew` to the NT headers, list
  sections and imports. You've hand-built an import table; now read one.
  Check your results against WinDbg's `!dh`.
* **DLLs**: FASM can build them (`format PE64 DLL`, `section '.edata' export`,
  the `export` macro). Write a DLL in asm and call it from a C or Python
  program (`ctypes`).
* **Structured exception handling**: x64 SEH is table-based. FASM can emit
  `.pdata`/`.xdata` sections by hand — read Microsoft's "x64 exception
  handling" docs. This also makes WinDbg's stack traces exact.

### Networking
* **UDP chat** with broadcast discovery (`SO_BROADCAST`, `sendto`
  255.255.255.255).
* **Non-blocking I/O**: `ioctlsocket(FIONBIO)` + `select`, or
  `WSAEventSelect` / `WSAAsyncSelect` — the latter posts socket events as
  window messages, which would remove NetSketch's thread entirely.
* **HTTPS** with WinHTTP (easy) or Schannel (hard, educational).
* **A real HTTP server** that serves files from a folder: parse the request
  line, map the path, `CreateFileA`, send headers + body.

## Tools worth learning

| Tool | Why |
|------|-----|
| **WinDbg Time Travel Debugging (TTD)** | Record a run, then step *backwards*. In WinDbg: *File → Start debugging → Launch executable (advanced)* → *Record with Time Travel Debugging*. Then `g-`, `p-`, `t-` go back in time, and `ba w8` + `g-` finds *who last wrote* a value. Mind-blowing for asm. |
| **x64dbg** | A friendly open-source GUI debugger; good companion to WinDbg. |
| **Process Monitor** (Sysinternals) | See every file/registry/network operation your program makes. |
| **Process Explorer** | Threads, handles, GDI objects per process. |
| **Wireshark** | See NetSketch's and http_get's packets on the wire (use the *Adapter for loopback traffic capture* for 127.0.0.1). |
| **Compiler Explorer** (godbolt.org) | Write C, see the x64 a compiler produces (choose MSVC for the Windows ABI). Steal ideas, learn idioms. |
| **fasmg / fasm2** | Tomasz Grysztar's next-generation assembler engine; fasm2 is mostly compatible with the syntax used here. |

## References

* **Intel® 64 and IA-32 Architectures Software Developer's Manuals** — the
  definitive instruction reference (Volume 2). Huge, but searchable.
  Felix Cloutier's <https://www.felixcloutier.com/x86/> is the same content as
  web pages.
* **Microsoft x64 calling convention**: search "x64 calling convention
  Microsoft Learn" and "x64 stack usage".
* **Win32 API docs**: <https://learn.microsoft.com/windows/win32/api/> — every
  function used in this course. Read the "Return value" section every time.
* **FASM manual**: `FASM.PDF` in your FASM folder, and
  <https://flatassembler.net/docs.php>. The forum at
  <https://board.flatassembler.net> is active and friendly.
* **WinDbg docs**: search "WinDbg debugger commands Microsoft Learn"; the
  `.hh` command in WinDbg opens the help for any command (`.hh bp`).
* **Agner Fog's optimisation manuals** (<https://agner.org/optimize/>) when you
  start caring about speed: instruction latencies, how the CPU pipelines
  really work.

## A suggested habit

For every new API or instruction you meet:

1. Read its documentation (arguments, return value, failure behaviour).
2. Call it in the smallest possible program.
3. Put a breakpoint on it in WinDbg and look at the arguments going in and the
   results coming out.

That three-step loop is how everything in this course was built, and it will
get you through anything Windows throws at you.
