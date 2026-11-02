# x86-64 Assembly on Windows with FASM + WinDbg

A hands-on course that takes you from "what is a register?" to writing a real
Windows application in pure assembly that **opens a window, draws lines with
its own line-drawing algorithm, and talks over the network** — and teaches you
to *see* every one of those steps happening inside **WinDbg**.

You will not just read code. Every lesson has a program you assemble with
**FASM** (flat assembler) and then take apart in **WinDbg**: stepping
instructions, watching registers and memory change, setting breakpoints on
Windows API calls, and checking that what you *think* happens is what
*actually* happens. That debugger-first habit is what lets you go off and
explore on your own afterwards.

## What you'll build

| Lesson | Program | What you learn |
|-------:|---------|----------------|
| 00 | – | Installing FASM and WinDbg, the build/debug loop |
| 01 | `exit.exe` | The smallest PE64 program, a hand-built import table, your first WinDbg session |
| 02 | `registers.exe` | Registers, arithmetic, flags; reading `r` output in WinDbg |
| 03 | `memory.exe` | Data, addressing modes, little-endian, the stack, hardware watchpoints |
| 04 | `control.exe` | Compare/jump, loops, switch tables, functions, recursion, the call stack |
| 05 | `hello_raw.exe` | The Windows x64 calling convention, done fully by hand |
| 06 | `hello_macros.exe` | FASM's `invoke`/`proc`/`import` macros — and what they expand to |
| 07 | `calc.exe` | A reusable console library: printing, reading, number⇄text |
| 08 | `wc.exe` | Command line, files, heap memory — a `wc` clone |
| 09 | `window.exe` | A real Win32 window, the message loop, the window procedure |
| 10 | `gdi_lines.exe` | **Drawing lines** with GDI pens, loops of lines, shapes, text |
| 11 | `paint.exe` | Your own **pixel framebuffer + Bresenham line algorithm** + mouse painting |
| 12 | `echo_server.exe` / `echo_client.exe` | **TCP networking** with Winsock |
| 13 | `http_get.exe` | DNS lookup + talking HTTP to a real web server |
| 14 | `netsketch.exe` | **Capstone:** a networked shared whiteboard (threads + GUI + sockets) |

Reference material:

* [`docs/windbg-cheatsheet.md`](docs/windbg-cheatsheet.md) — every WinDbg command used in the course, plus more
* [`docs/fasm-cheatsheet.md`](docs/fasm-cheatsheet.md) — FASM syntax, directives and macros
* [`docs/x64-reference.md`](docs/x64-reference.md) — registers, common instructions, condition codes, the calling convention on one page
* [`docs/15-next-steps.md`](docs/15-next-steps.md) — ideas and pointers for exploring on your own

## Course

0. [Setup: FASM, WinDbg and the workflow](docs/00-setup.md)
1. [Your first program (and your first debugging session)](docs/01-first-program.md)
2. [Registers, arithmetic and flags](docs/02-registers.md)
3. [Memory, addressing and the stack](docs/03-memory.md)
4. [Control flow and functions](docs/04-control-flow.md)
5. [The Windows x64 calling convention](docs/05-calling-convention.md)
6. [FASM macros: `invoke`, `proc`, `import`](docs/06-macros.md)
7. [A console toolkit: strings, numbers, input](docs/07-console.md)
8. [Files, heap and the command line](docs/08-files.md)
9. [Opening a window](docs/09-window.md)
10. [Drawing lines with GDI](docs/10-gdi.md)
11. [Your own pixels: framebuffer and Bresenham](docs/11-framebuffer.md)
12. [TCP networking with Winsock](docs/12-sockets.md)
13. [DNS and HTTP](docs/13-http.md)
14. [Capstone: NetSketch, a networked whiteboard](docs/14-netsketch.md)
15. [Where to go next](docs/15-next-steps.md)

## Repository layout

```
docs/                  the lessons (read these in order)
examples/
  common/              reusable include files you build up during the course
    console.inc        print / read / number conversion   (lesson 07)
    framebuffer.inc    pixel buffer + Bresenham line      (lesson 11)
    ws2_32.inc         Winsock imports and constants      (lesson 12)
  01-exit/ ... 14-netsketch/   one folder per lesson
build.bat              assembles every example
```

## Quick start

```bat
:: one-time (see docs/00-setup.md for details)
set PATH=%PATH%;C:\fasm
set INCLUDE=C:\fasm\INCLUDE

:: build everything
build.bat

:: run a lesson under the debugger
windbgx examples\01-exit\exit.exe
```

## Prerequisites

* Windows 10 or 11, 64-bit
* Comfort with a command prompt
* Any prior programming in *some* language helps (you should know what a
  variable, loop and function are). No prior assembly needed.

## Philosophy

* **Small, complete programs.** Every example assembles to a standalone `.exe`
  with no C runtime and no linker — FASM writes the PE file directly.
* **Raw first, macros second.** You'll hand-build an import table and hand-set
  up a call to a Windows API *before* letting macros do it, so the macros never
  feel like magic.
* **The debugger is your eyes.** Each lesson ends with "Explore in WinDbg"
  exercises. Do them. They're where the learning actually happens.
